require "test_helper"

class ConsoleFlowTest < ActionDispatch::IntegrationTest
  test "unauthenticated users are redirected to sign in" do
    get cases_path
    assert_redirected_to new_session_path
  end

  test "inactive users cannot sign in" do
    post session_path, params: { email_address: users(:inactive).email_address, password: "password" }
    assert_redirected_to new_session_path
    get cases_path
    assert_redirected_to new_session_path
  end

  test "login is audited" do
    assert_difference -> { AuditEntry.where(action: "user.login").count } do
      post session_path, params: { email_address: users(:admin).email_address, password: "password" }
    end
  end

  test "admin can run a case through its lifecycle in the console" do
    sign_in_as users(:admin)

    post cases_path, params: { case: {
      subject: "New grievance", contact_id: contacts(:asha).id,
      queue_id: queues(:pensions).id, priority: "high",
      sla_policy_id: sla_policies(:standard).id
    } }
    kase = Case.order(:id).last
    assert_redirected_to case_path(kase)
    assert_equal "staff", kase.channel
    assert kase.first_response_due_at.present?

    post transition_case_path(kase), params: { status: "triaged" }
    assert_equal "triaged", kase.reload.status

    post assign_case_path(kase), params: { assignee_id: users(:agent_a).id }
    assert_equal users(:agent_a), kase.reload.assignee

    post case_messages_path(kase), params: { message: { body: "We are reviewing.", kind: "public_reply" } }
    assert kase.reload.first_responded_at.present?

    post transition_case_path(kase), params: { status: "in_progress" }
    post transition_case_path(kase), params: { status: "resolved" }
    assert_equal "resolved", kase.reload.status
  end

  test "illegal transition shows a friendly error not a stack trace" do
    sign_in_as users(:admin)
    post transition_case_path(cases(:pension_case)), params: { status: "closed" }
    assert_redirected_to root_path
    assert_equal "new", cases(:pension_case).reload.status
  end

  test "readonly users get 403 on mutations" do
    sign_in_as users(:readonly)
    get new_case_path
    assert_response :forbidden
    post cases_path, params: { case: { subject: "Nope", contact_id: contacts(:asha).id } }
    assert_response :forbidden
    post case_messages_path(cases(:pension_case)), params: { message: { body: "Nope" } }
    assert_response :forbidden
  end

  test "non-admins get 403 on user management" do
    sign_in_as users(:supervisor)
    get admin_users_path
    assert_response :forbidden
    post admin_users_path, params: { user: { name: "X", email_address: "x@example.com", password: "password1234" } }
    assert_response :forbidden
  end

  test "agents cannot edit cases assigned to others outside their queues" do
    sign_in_as users(:agent_b)
    patch case_path(cases(:assigned_case)), params: { case: { subject: "Hijack" } }
    assert_response :forbidden
  end

  test "mass-assigning status through update is ignored by strong params" do
    sign_in_as users(:admin)
    patch case_path(cases(:pension_case)), params: { case: { subject: "Updated", status: "closed" } }
    kase = cases(:pension_case).reload
    assert_equal "Updated", kase.subject
    assert_equal "new", kase.status
  end

  test "staff composer cannot forge agent turns" do
    sign_in_as users(:admin)
    post case_messages_path(cases(:pension_case)), params: { message: { body: "Fake AI", kind: "agent_turn" } }
    assert_equal "public_reply", Message.order(:id).last.kind
  end

  test "case list filters by status and queue" do
    sign_in_as users(:admin)
    get cases_path, params: { status: "in_progress", queue_id: queues(:sanitation).id }
    assert_response :success
    assert_select "td", text: cases(:assigned_case).tracking_id
    assert_select "td", { text: cases(:pension_case).tracking_id, count: 0 }
  end

  test "locale toggle switches to hindi" do
    sign_in_as users(:admin)
    post locale_path(locale: "hi")
    get cases_path
    assert_select "h1", text: I18n.t("cases.index.title", locale: :hi)
  end

  test "deleting a case soft-deletes and audits" do
    sign_in_as users(:admin)
    kase = cases(:resolved_case)
    assert_difference -> { AuditEntry.where(action: "case.delete").count } do
      delete case_path(kase)
    end
    refute Case.exists?(kase.id)
    assert Case.with_deleted.exists?(kase.id)
  end
end
