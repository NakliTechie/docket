require "test_helper"

# Gate G2 artifact: the full service loop —
# citizen submits → agent replies → resolve → reopen.
class CitizenJourneyTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "full loop: submit, triage, reply, resolve, reopen" do
    # Citizen files via the public portal.
    post portal_cases_path, params: { portal_submission: {
      name: "Kavita Sharma", email: "kavita@example.com",
      subject: "Pension arrears pending",
      description: "Arrears for January–March not received."
    } }
    assert_response :created
    kase = Case.order(:id).last

    # Agent picks it up in the console.
    sign_in_as users(:supervisor)
    post transition_case_path(kase), params: { status: "triaged" }
    post assign_case_path(kase), params: { assignee_id: users(:agent_a).id }
    post transition_case_path(kase), params: { status: "in_progress" }

    # Agent replies publicly — citizen is emailed, first response stamped.
    assert_enqueued_emails 1 do
      post case_messages_path(kase), params: { message: {
        body: "Your arrears have been processed and will credit within 3 days.",
        kind: "public_reply"
      } }
    end
    assert kase.reload.first_responded_at.present?

    # Resolve.
    post transition_case_path(kase), params: { status: "resolved" }
    assert_equal "resolved", kase.reload.status
    assert kase.resolved_at.present?

    # Citizen disputes via the portal → reopen by staff.
    post portal_track_reply_path, params: {
      tracking_id: kase.tracking_id, contact_email: "kavita@example.com",
      body: "Credit has not arrived."
    }
    post transition_case_path(kase), params: { status: "reopened" }
    assert_equal "reopened", kase.reload.status
    assert_equal 1, kase.reopen_count

    # The whole journey is on the audit chain.
    result = AuditEntry.verify_chain
    assert result[:ok], result.inspect
    actions = AuditEntry.where(auditable: kase).pluck(:action)
    assert_includes actions, "case.create"
    assert actions.count("case.update") >= 4
  end
end
