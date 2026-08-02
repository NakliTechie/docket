require "test_helper"

class PortalDecisionsTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:customer_oidc] = OmniAuth::AuthHash.new(
      provider: "customer_oidc", uid: contacts(:ravi).external_id,
      info: { email: "ravi@example.test", name: contacts(:ravi).name },
      extra: { raw_info: {} }
    )
    get "/auth/customer_oidc/callback"
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:customer_oidc)
  end

  test "customer sees applied decisions of record concerning them and their cases" do
    direct = applied_decision(contacts(:ravi), label: "Direct customer decision")
    case_decision = applied_decision(cases(:resolved_case), label: "Owned case decision")
    hidden = applied_decision(cases(:pension_case), label: "Other customer decision")
    autonomous = Decision.create!(rule: "internal", version: "1", subject: contacts(:ravi),
                                  subject_label: "Internal signal", signal: "signal",
                                  decision_class: "autonomous", status: :applied)

    get portal_decisions_path

    assert_response :success
    assert_match direct.subject_label, response.body
    assert_match case_decision.subject_label, response.body
    assert_no_match hidden.subject_label, response.body
    assert_no_match autonomous.subject_label, response.body
  end

  test "customer files one pending appeal with their identity attached" do
    decision = applied_decision(cases(:resolved_case), label: "Appealable")

    assert_difference "DecisionAppeal.count", 1 do
      post appeal_portal_decision_path(decision), params: { grounds: "The case evidence was incomplete." }
    end
    appeal = DecisionAppeal.order(:id).last
    assert_redirected_to portal_decisions_path
    assert_equal contacts(:ravi), appeal.appellant
    assert_equal "The case evidence was incomplete.", appeal.grounds

    assert_no_difference "DecisionAppeal.count" do
      post appeal_portal_decision_path(decision), params: { grounds: "A duplicate pending appeal." }
    end
    assert_redirected_to portal_decisions_path
  end

  test "decision rule names are localized in the customer portal" do
    applied_decision(cases(:resolved_case), label: "Localized decision", rule: "routing_suggestion")
    post locale_path(locale: "hi")

    get portal_decisions_path

    assert_response :success
    assert_match I18n.t("decisioning.rules.routing_suggestion", locale: :hi), response.body
    assert_match I18n.t("portal.decisions.index.title", locale: :hi), response.body
  end

  test "customer cannot appeal another contact's decision" do
    decision = applied_decision(cases(:pension_case), label: "Not Ravi's")

    assert_no_difference "DecisionAppeal.count" do
      post appeal_portal_decision_path(decision), params: { grounds: "Probe" }
    end
    assert_response :not_found
  end

  test "signed-out visitor is redirected before decisions are disclosed" do
    delete portal_customer_session_path
    get portal_decisions_path
    assert_redirected_to portal_root_path
  end

  private

  def applied_decision(subject, label:, rule: "eligibility_review")
    Decision.create!(rule: rule, version: "1", subject: subject,
                     subject_label: label, signal: SecureRandom.hex(4), recommendation: "Decision outcome",
                     decision_class: "of_record", status: :applied,
                     approved_by: users(:decision_reviewer), decision_reason: "Evidence reviewed",
                     decided_at: Time.current)
  end
end
