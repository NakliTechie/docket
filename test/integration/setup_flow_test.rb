require "test_helper"

class SetupFlowTest < ActionDispatch::IntegrationTest
  test "a platform administrator can use the resumable first-run checklist" do
    sign_in_as users(:admin)

    get setup_path

    assert_response :success
    assert_select "h1", text: I18n.t("setups.show.title")
    assert_select "[data-controller=clipboard]", minimum: 1
    assert_select "section.setup-resource[data-controller=clipboard]", count: 1
    assert_select "ol.setup-list > li", count: 6
    assert_select "a[href='#{portal_root_path}']", minimum: 1
    assert_match I18n.t("setups.show.email.not_configured"), response.body
    assert_equal true, Setting.get("setup_started")
  end

  test "workspace naming stays inside setup" do
    sign_in_as users(:admin)

    patch setup_path, params: { step: "brand", brand_name: "Northstar Support" }

    assert_redirected_to setup_path
    assert_equal "Northstar Support", Setting.get("brand_name")
  end

  test "non-platform roles cannot reach setup" do
    sign_in_as users(:client_admin)

    get setup_path

    assert_response :forbidden
  end

  test "a genuinely empty platform tenant lands on setup" do
    make_tenant_fresh
    sign_in_as users(:admin)

    get root_path

    assert_redirected_to setup_path
  end

  test "started setup remains home until it is deliberately finished" do
    sign_in_as users(:admin)
    get setup_path

    get root_path

    assert_redirected_to setup_path
  end

  test "service desk first value requires assignment reply and resolution" do
    Current.tenant = tenants(:primary)
    Case.update_all(deleted_at: Time.current)
    kase = Case.create!(
      subject: "First setup request",
      contact: contacts(:asha),
      queue: queues(:pensions),
      sla_policy: sla_policies(:standard),
      channel: :web_portal
    )

    progress = SetupProgress.new(actor: users(:admin), base_url: "https://docket.example")
    assert progress.first_record?
    refute progress.first_value?

    kase.update!(assignee: users(:agent_a))
    kase.messages.create!(body: "We are on it", kind: :public_reply,
                          direction: :outbound, author: users(:agent_a))
    kase.transition_to!(:in_progress)
    kase.transition_to!(:resolved)

    assert SetupProgress.new(actor: users(:admin), base_url: "https://docket.example").first_value?
  end

  test "complete setup exposes and accepts an explicit finish transition" do
    Case.update_all(deleted_at: Time.current)
    kase = Case.create!(subject: "Finish setup", contact: contacts(:asha),
                        assignee: users(:agent_a), channel: :web_portal)
    kase.messages.create!(body: "Resolved", kind: :public_reply,
                          direction: :outbound, author: users(:agent_a))
    kase.transition_to!(:in_progress)
    kase.transition_to!(:resolved)
    Setting.set("brand_name", "Northstar")
    Setting.set("setup_modules_confirmed", true)
    Setting.set("setup_email_skipped", true)
    sign_in_as users(:admin)

    get setup_path
    assert_select "button", text: I18n.t("setups.show.complete.action")

    patch setup_path, params: { step: "finish" }

    assert_redirected_to root_path
    assert_equal true, Setting.get("setup_finished")
    follow_redirect!
    assert_redirected_to dashboard_path
  end

  test "the empty inbox hides steady-state filters and exposes the portal" do
    Case.update_all(deleted_at: Time.current)
    sign_in_as users(:admin)

    get cases_path

    assert_response :success
    assert_select "form.filter-bar", count: 0
    assert_select "button", text: I18n.t("cases.index.empty.copy_portal")
    assert_match portal_root_path, response.body
  end

  test "a filtered empty result keeps filters and explains recovery" do
    sign_in_as users(:admin)

    get cases_path(q: "definitely-no-case-matches")

    assert_response :success
    assert_select "form.filter-bar", count: 1
    assert_select ".empty-state-title", text: I18n.t("cases.index.no_matches.title")
  end

  test "setup records explicit defer and confirmation choices" do
    sign_in_as users(:admin)

    patch setup_path, params: { step: "email" }
    assert_redirected_to setup_path
    assert_equal true, Setting.get("setup_email_skipped")

    patch setup_path, params: { step: "modules" }
    assert_equal true, Setting.get("setup_modules_confirmed")
  end

  test "role landings reflect the primary job" do
    sign_in_as users(:sales)
    get root_path
    assert_redirected_to leads_path

    reset!
    sign_in_as users(:finance)
    get root_path
    assert_redirected_to dashboard_path

    reset!
    sign_in_as users(:technical)
    get root_path
    assert_redirected_to admin_connectors_path

    reset!
    sign_in_as users(:customer_service_supervisor)
    get root_path
    assert_redirected_to dashboard_path

    reset!
    sign_in_as users(:decision_reviewer)
    get root_path
    assert_redirected_to dashboard_path

    reset!
    sign_in_as users(:knowledge_manager)
    get root_path
    assert_redirected_to admin_reference_docs_path

    reset!
    sign_in_as users(:auditor)
    get root_path
    assert_redirected_to dashboard_path
  end

  private

  def make_tenant_fresh
    [ Case, Lead, Project ].each { |model| model.update_all(deleted_at: Time.current) }
  end
end
