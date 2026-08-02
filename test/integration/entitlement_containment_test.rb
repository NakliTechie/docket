require "test_helper"

# Regression cover for the containment holes an adversarial review found after
# the first ENT commit. Every test here maps to a path that WAS reachable for a
# tenant that hadn't bought the module. The controller guard was never the whole
# story: anything running outside a request, and any surface whose access gate
# is an unmapped permission, needed its own check.
class EntitlementContainmentTest < ActionDispatch::IntegrationTest
  def disable!(key) = ActsAsTenant.current_tenant.set_feature!(key, false)

  # ── Shared surfaces that embed another module's data ──────────────────────
  test "a contact page hides case history when the service desk is off" do
    disable!("service_desk")
    sign_in_as users(:admin)

    get contact_path(contacts(:asha))
    assert_response :success, "contacts are shared by every module — the page itself stays"
    refute_match cases(:pension_case).subject, response.body,
                 "case subjects must not leak through the contact record"
    refute_match cases(:pension_case).tracking_id, response.body
  end

  test "a contact page and agent catalogs hide CRM conversations when CRM is off" do
    CrmMessage.create!(subject: contacts(:asha), body: "Seller-only thread marker",
                       direction: :inbound, delivery_status: :recorded,
                       sender_email: contacts(:asha).email)
    disable!("crm")
    sign_in_as users(:admin)

    get contact_path(contacts(:asha))
    assert_response :success
    refute_match "Seller-only thread marker", response.body
    refute_match I18n.t("crm_messages.title"), response.body

    Mcp::Catalog.reset!
    get "/api/v1/openapi.json"
    refute_includes response.parsed_body["paths"].keys, "/crm_messages"
  ensure
    Mcp::Catalog.reset!
  end

  test "the command palette neither links to nor enumerates a disabled module" do
    disable!("service_desk")
    sign_in_as users(:admin)

    get contacts_path
    assert_response :success
    refute_match 'data-palette-href="/cases"', response.body
    CaseQueue.pluck(:name).each do |queue_name|
      refute_match queue_name, response.body, "queue names are desk data"
    end
  end

  test "dashboard panes follow their module" do
    disable!("crm")
    sign_in_as users(:admin)

    get dashboard_path
    assert_response :success
    refute_match I18n.t("dashboards.index.sales"), response.body
    assert_match I18n.t("dashboards.index.case_desk"), response.body, "the desk pane stays"
  end

  test "the case-activity API report is desk data and follows the desk" do
    disable!("service_desk")
    token = api_token_for(users(:admin))

    get "/api/v1/reports/activity", headers: auth_header(token)
    assert_response :forbidden
    assert_equal "feature_disabled", JSON.parse(response.body)["error"]
  end

  # ── Signing in must land somewhere that exists ────────────────────────────
  test "a tenant without the service desk still gets a usable home page" do
    ActsAsTenant.current_tenant.apply_preset!("crm_only")
    sign_in_as users(:admin)

    get root_path
    assert_redirected_to dashboard_path, "an administrator should land on usable insights"
    follow_redirect!
    assert_response :success
  end

  test "root sends an administrator with operational data to insights" do
    sign_in_as users(:admin)
    get root_path
    assert_redirected_to dashboard_path
  end

  # ── Endpoints that move data outside the console ──────────────────────────
  test "the connector webhook stops ingesting when connectors are off" do
    connector = Connector.create!(name: "Sync", provider: "http_json", status: :active,
                                  config: { "base_url" => "https://example.test" },
                                  field_mapping: { "email" => "email", "name" => "name" })
    disable!("connectors")

    # What matters is that nothing is ingested and no sync is enqueued. (A JSON
    # request gets the API's 403 feature_disabled shape rather than the HTML
    # 404 — same refusal, diagnosable to the caller.)
    assert_no_enqueued_jobs only: ConnectorSyncJob do
      post connector_webhook_path(connector), params: {}, as: :json
    end
    assert_response :forbidden
    assert_equal "feature_disabled", JSON.parse(response.body)["error"]
  end

  # ── Background work ───────────────────────────────────────────────────────
  test "recurring sweeps skip tenants without the module" do
    ActsAsTenant.without_tenant do
      tenants(:primary).set_feature!("service_desk", false)
      tenants(:primary).set_feature!("crm.sequences", false)
      tenants(:primary).set_feature!("decisioning", false)

      swept = []
      ApplicationJob.new.send(:each_tenant_with_feature, "service_desk") { swept << ActsAsTenant.current_tenant }
      refute_includes swept.map(&:id), tenants(:primary).id, "a tenant without the desk must not be swept"
      assert_includes swept.map(&:id), tenants(:acme).id, "a tenant that HAS it still is"

      kept = []
      ApplicationJob.new.send(:each_tenant_with_feature, "work") { kept << ActsAsTenant.current_tenant }
      assert_includes kept.map(&:id), tenants(:primary).id, "modules it DOES have still sweep"
    end
  end

  test "inbound mail cannot open a case for a tenant without the desk" do
    disable!("service_desk")

    assert_no_difference "Case.count" do
      mail = Mail.new(from: "asha@example.com", to: "support@docket.local",
                      subject: "Help", body: "please")
      inbound = ActionMailbox::InboundEmail.create_and_extract_message_id!(mail.to_s)
      CasesMailbox.new(inbound).process
      assert inbound.reload.bounced? || Case.count.zero?
    end
  end

  test "the effector gate closes for service accounts too, not just staff" do
    account = ServiceAccount.create!(name: "Agent", scopes: %w[connectors:invoke])
    assert Connectors::Authorization.may_invoke?(account), "sanity: normally permitted"

    disable!("connectors")
    refute Connectors::Authorization.may_invoke?(account),
           "the AI agent runs as a service account — the gate must apply to it"
  end

  # ── Agent-facing surfaces ─────────────────────────────────────────────────
  test "the MCP tool list and the OpenAPI document drop a disabled module" do
    disable!("crm")
    Mcp::Catalog.reset!

    tool_names = Mcp::Catalog.tools.map { |t| t["name"] }
    assert tool_names.any? { |n| n.include?("cases") }, "sanity: the desk is still listed"
    refute tool_names.any? { |n| n.include?("leads") }, "no tools for a module the tenant lacks"

    get "/api/v1/openapi.json"
    paths = JSON.parse(response.body)["paths"].keys
    refute paths.any? { |p| p.start_with?("/leads") }
    assert paths.any? { |p| p.start_with?("/cases") }
  end

  # ── Resolution-layer robustness ───────────────────────────────────────────
  test "a non-boolean override denies rather than silently enabling" do
    tenant = ActsAsTenant.current_tenant
    tenant.update_column(:entitlements, { "crm" => "false" })

    refute tenant.reload.feature?("crm"), "the string 'false' is not permission to run"
    tenant.update_column(:entitlements, { "crm" => 0 })
    refute tenant.reload.feature?("crm")
  end

  test "nil entitlements are rejected by validation and never crash a read" do
    tenant = ActsAsTenant.current_tenant
    tenant.entitlements = nil
    refute tenant.valid?, "nil cannot be persisted"

    # Read-time it degrades to the documented default (no overrides = all on)
    # rather than raising. It used to blow up in feature?, turning every gated
    # request into a 500 instead of an answer. The column is NOT NULL with a {}
    # default, so nil is only ever a transient in-memory state.
    assert_nothing_raised { tenant.feature?("crm") }
    assert tenant.feature?("crm")
  end

  test "the ambient request tenant is authoritative for entitlements" do
    tenants(:acme).set_feature!("crm", false)
    admin = users(:admin) # belongs to primary, where crm is on

    ActsAsTenant.with_tenant(tenants(:acme)) do
      refute admin.can?("lead:read"), "a platform operator is constrained by the tenant being served"
    end

    ActsAsTenant.current_tenant.set_feature!("crm", false)
    refute admin.can?("lead:read"), "the user's own tenant remains the fallback"
  end

  test "work API paths and MCP tools drop with the work module" do
    tenant = ActsAsTenant.current_tenant
    tenant.set_feature!("work", false)
    tenant.set_feature!("work.sprints", false)

    # Re-enter with a freshly loaded tenant: the ambient instance still holds
    # the entitlements it was loaded with.
    ActsAsTenant.with_tenant(Tenant.find(tenant.id)) do
      Mcp::Catalog.reset!
      work_tools = Mcp::Catalog.tools.map { |t| t["name"] }.select { |n| n =~ /work_item|project|sprint/ }
      assert_empty work_tools, "an agent must not be handed tools for a module the tenant lacks"

      %w[/projects /work_items /sprints /work_items/{id}/transition].each do |path|
        refute Features.api_path_enabled?(path), "#{path} should be filtered out of the spec"
      end
    end
  ensure
    Mcp::Catalog.reset!
  end

  test "the module count in the console is derived, not hand-listed" do
    assert_equal Features::REGISTRY.keys.reject { |k| k.include?(".") }, Features.modules,
                 "a hand-written module list goes stale the next time a module is added"
  end

  # ── Regressions from the 2026-07-28 work-module review ────────────────────
  test "an importer cannot conjure a module the tenant does not have" do
    disable!("work")
    payload = { "issues" => [ { "key" => "ZZ-1", "fields" => { "summary" => "should not exist" } } ] }

    assert_no_difference [ "Project.count", "WorkItem.count" ] do
      result = Imports::Jira.call(payload: payload, actor: users(:admin))
      assert result.errors.any?, "and it must say why, not fail silently"
    end
  end

  test "a disabled module's webhooks do not leave the building" do
    WebhookEndpoint.create!(name: "eng", url: "https://example.test/hook",
                            events: %w[work_item.created], active: true)
    item_attrs = { title: "phantom", reporter: users(:admin) }

    assert_difference "WebhookDelivery.count", 1 do
      projects(:pep).work_items.create!(**item_attrs)
    end

    disable!("work")
    assert_no_difference "WebhookDelivery.count" do
      ActsAsTenant.with_tenant(Tenant.find(ActsAsTenant.current_tenant.id)) do
        Project.with_deleted.find(projects(:pep).id).work_items.create!(title: "phantom 2",
                                                                       reporter: users(:admin))
      end
    end
  end

  test "with sprints off the board neither names a sprint nor filters by one" do
    sprint = projects(:pep).sprints.create!(name: "Secret Sprint", status: :active)
    work_items(:pep_one).update!(sprint: sprint)
    disable!("work.sprints")
    sign_in_as users(:admin)

    get project_board_path(projects(:pep))
    assert_response :success
    refute_match "Secret Sprint", response.body, "a disabled sub-feature must not name its data"
    assert_match work_items(:pep_two).reference, response.body,
                 "and must not silently filter the board down to that sprint"
  end
end
