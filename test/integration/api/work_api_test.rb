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

    test "the work API follows the work entitlement" do
      ActsAsTenant.current_tenant.set_feature!("work", false)

      get "/api/v1/projects", headers: auth_header(@token)
      assert_response :forbidden
      assert_equal "feature_disabled", JSON.parse(response.body)["error"]
    end

    test "a service account needs the work scope" do
      account = ServiceAccount.create!(name: "Bot", scopes: %w[cases:read])
      assert_not account.scope?("work:read")

      with_work = ServiceAccount.create!(name: "WorkBot", scopes: %w[work:read work:write])
      assert with_work.scope?("work:write")
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
