require "test_helper"

class AdminSurfacesTest < ActionDispatch::IntegrationTest
  test "activity view is admin-only" do
    sign_in_as users(:supervisor)
    get admin_activity_path
    assert_response :forbidden

    sign_in_as users(:admin)
    get admin_activity_path
    assert_response :success
  end

  test "activity view aggregates audit data and exports csv" do
    sign_in_as users(:admin)
    Current.set(actor: users(:agent_a)) do
      Contact.create!(name: "Generated", email: "generated@example.com")
    end

    get admin_activity_path
    assert_response :success
    assert_match users(:agent_a).name, response.body

    get admin_activity_path(format: :csv)
    assert_response :success
    assert_match "contact.create", response.body
    assert_match users(:agent_a).email_address, response.body
  end

  test "audit chain page shows verification status" do
    sign_in_as users(:admin)
    Contact.create!(name: "Chained", email: "chained@example.com")
    get admin_audit_path
    assert_response :success
    assert_match I18n.t("admin.audit.show.intact"), response.body
  end

  test "audit chain page reports tampering" do
    sign_in_as users(:admin)
    contact = Contact.create!(name: "Tampered", email: "tampered@example.com")
    entry = AuditEntry.where(auditable: contact).first
    AuditEntry.connection.execute("UPDATE audit_entries SET action = 'contact.forged' WHERE id = #{entry.id}")
    get admin_audit_path
    assert_match I18n.t("admin.audit.show.broken"), response.body
  end

  test "macros are insertable metadata on messages" do
    sign_in_as users(:admin)
    macro = Macro.create!(name: "Ack", body: "Dear {{contact_name}}, we have received your case.")
    post case_messages_path(cases(:pension_case)), params: {
      macro_id: macro.id,
      message: { body: "Dear Asha Rao, we have received your case.", kind: "public_reply" }
    }
    message = Message.order(:id).last
    assert_equal macro.id, message.metadata["macro_id"]
  end

  test "macro management denied to agents" do
    sign_in_as users(:agent_a)
    get macros_path
    assert_response :success
    post macros_path, params: { macro: { name: "Nope", body: "Nope" } }
    assert_response :forbidden
  end
end
