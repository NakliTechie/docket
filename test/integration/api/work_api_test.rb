require "test_helper"

module Api
  # WM5 — the work module over api/v1, plus its webhook events and the
  # agent-facing effector action.
  class WorkApiTest < ActionDispatch::IntegrationTest
    setup { @token = api_token_for(users(:admin)) }

    test "projects and work items are listable and creatable" do
      get "/api/v1/projects", headers: auth_header(@token)
      assert_response :success
      assert_includes JSON.parse(response.body)["data"].map { |p| p["key"] }, "PEP"

      post "/api/v1/work_items",
           params: { work_item: { project_id: projects(:pep).id, title: "From the API", kind: "bug" } },
           headers: auth_header(@token), as: :json
      assert_response :created
      body = JSON.parse(response.body)["data"]
      assert_equal "PEP-3", body["reference"], "the API mints identity the same way the console does"
      assert_equal "bug", body["kind"]
    end

    test "an API transition audits and echoes exactly like a console move" do
      item = work_items(:pep_one)
      WorkLink.create!(work_item: item, linkable: cases(:pension_case), relation: :escalated_from)

      # Two audit entries, not one: the item's own transition plus the internal
      # note echoed onto the linked case. Both belong in the chain.
      assert_difference "AuditEntry.count", 2 do
        assert_difference -> { cases(:pension_case).messages.count }, 1 do
          post "/api/v1/work_items/#{item.id}/transition",
               params: { workflow_state_id: workflow_states(:pep_done).id },
               headers: auth_header(@token), as: :json
        end
      end
      assert_response :success
      assert item.reload.done?
    end

    test "sprints close over the API and report what moved" do
      sprint = projects(:pep).sprints.create!(name: "S1", status: :active)
      work_items(:pep_one).update!(sprint: sprint)

      post "/api/v1/sprints/#{sprint.id}/close", headers: auth_header(@token), as: :json
      assert_response :success
      assert_equal 1, JSON.parse(response.body)["moved_items"]
      assert sprint.reload.status_closed?
    end

    test "the sprint report is available over the API" do
      sprint = projects(:pep).sprints.create!(name: "Measured", status: :active)
      item = work_items(:pep_two)
      item.update!(sprint: sprint, estimate: 5)
      item.transition_to!(workflow_states(:pep_done))

      get "/api/v1/projects/#{projects(:pep).id}/sprint_report", headers: auth_header(@token)

      assert_response :success
      data = response.parsed_body["data"]
      assert_equal projects(:pep).id, data["project_id"]
      row = data["sprints"].find { |candidate| candidate["sprint_id"] == sprint.id }
      assert_equal 5.0, row["completed_estimate"]
      assert data.key?("cycle_time_days")
    end

    test "the work API follows the work entitlement" do
      ActsAsTenant.current_tenant.set_feature!("work", false)

      get "/api/v1/projects", headers: auth_header(@token)
      assert_response :forbidden
      assert_equal "feature_disabled", JSON.parse(response.body)["error"]
    end

    # These used to assert `account.scope?(...)` twice and never issue a request,
    # which is exactly how the hole below shipped: for a service account
    # authorize_api! checks ONLY the scope and Pundit never runs, so an endpoint
    # whose policy demands project:manage was gated on work:write.
    test "a work:write token cannot do project:manage work" do
      token = service_token_for(%w[work:read work:write])

      assert_no_difference "Project.count" do
        post "/api/v1/projects", params: { project: { key: "PWN", name: "Bot project" } },
             headers: auth_header(token), as: :json
      end
      assert_response :forbidden

      before = projects(:pep).key
      patch "/api/v1/projects/#{projects(:pep).id}",
            params: { project: { key: "ZZZ", name: "Renamed by bot" } },
            headers: auth_header(token), as: :json
      assert_response :forbidden
      assert_equal before, projects(:pep).reload.key,
                   "renaming the key rewrites the KEY-123 identity of every item in the project"

      delete "/api/v1/work_items/#{work_items(:pep_one).id}", headers: auth_header(token)
      assert_response :forbidden
      refute work_items(:pep_one).reload.deleted?
    end

    test "a work:manage token can, and work:read alone cannot even write" do
      manage = service_token_for(%w[work:read work:write work:manage])
      assert_difference "Project.count", 1 do
        post "/api/v1/projects", params: { project: { key: "OK", name: "Allowed" } },
             headers: auth_header(manage), as: :json
      end
      assert_response :created

      readonly = service_token_for(%w[work:read])
      post "/api/v1/work_items",
           params: { work_item: { project_id: projects(:pep).id, title: "nope" } },
           headers: auth_header(readonly), as: :json
      assert_response :forbidden
    end

    test "a service account can author a work comment with explicit attribution" do
      token = service_token_for(%w[work:read work:write])

      assert_difference "WorkComment.count", 1 do
        post "/api/v1/work_items/#{work_items(:pep_one).id}/work_comments",
             params: { work_comment: { body: "Automated build report" } },
             headers: auth_header(token), as: :json
      end

      assert_response :created
      comment = WorkComment.order(:id).last
      assert_instance_of ServiceAccount, comment.author
      assert_equal "ServiceAccount", response.parsed_body["data"]["author_type"]
      assert_equal comment.author_id, response.parsed_body["data"]["author_id"]
    end

    test "the sprint API cannot force a status and skip close-out" do
      sprint = projects(:pep).sprints.create!(name: "S1", status: :active)
      work_items(:pep_one).update!(sprint: sprint)
      token = service_token_for(%w[work:read work:write])

      patch "/api/v1/sprints/#{sprint.id}", params: { sprint: { status: "closed" } },
            headers: auth_header(token), as: :json

      refute sprint.reload.status_closed?,
             "closing must go through Closeout, which decides what happens to unfinished work"
      assert_equal sprint, work_items(:pep_one).reload.sprint
    end

    test "work events are published to subscribed webhooks" do
      WebhookEndpoint.create!(name: "eng", url: "https://example.test/hook",
                              events: %w[work_item.created work_item.transitioned], active: true)

      assert_difference "WebhookDelivery.count", 1 do
        projects(:pep).work_items.create!(title: "watched", reporter: users(:admin))
      end
      delivery = WebhookDelivery.order(:id).last
      assert_equal "work_item.created", delivery.event
      assert_match "PEP-", delivery.payload.to_s
    end

    test "the agent proposes work rather than opening it — confirm, never autonomous" do
      kase = cases(:pension_case)
      decision = Decision.create!(rule: "needs_engineering", version: "1", subject: kase,
                                  signal: "defect", decision_class: "confirm", status: :proposed,
                                  action: "open_work_item",
                                  action_params: { "project_id" => projects(:pep).id, "title" => "Agent-raised" })

      # A confirm-class decision sits proposed until a human releases it.
      assert decision.status_proposed?
      refute decision.autonomous?, "work is never opened autonomously"

      assert_difference "WorkItem.count", 1 do
        Decisioning::Dispatcher.perform_action!(decision)
      end
      item = WorkItem.order(:id).last
      assert_equal "Agent-raised", item.title
      assert_includes kase.reload.work_items, item

      # Overturning an appeal removes the work but keeps the trail.
      Decisioning::Dispatcher.reverse!(decision.reload)
      assert item.reload.deleted?, "soft-deleted, so what the agent did survives the reversal"
    end
  end
end
