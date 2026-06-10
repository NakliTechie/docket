require "test_helper"

class SsoTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:staff_oidc)
    OmniAuth.config.mock_auth.delete(:staff_saml)
    OmniAuth.config.mock_auth.delete(:customer_oidc)
  end

  def mock_staff_oidc(email:, name: "SSO User", groups: nil)
    OmniAuth.config.mock_auth[:staff_oidc] = OmniAuth::AuthHash.new(
      provider: "staff_oidc", uid: "idp-#{email}",
      info: { email: email, name: name },
      extra: { raw_info: groups ? { "groups" => groups } : {} }
    )
  end

  test "staff oidc login JIT-provisions an agent and audits" do
    mock_staff_oidc(email: "newstaff@example.com", name: "New Staff")
    assert_difference [ "User.count" ] do
      assert_difference -> { AuditEntry.where(action: "user.login_sso").count } do
        get "/auth/staff_oidc/callback"
      end
    end
    user = User.find_by(email_address: "newstaff@example.com")
    assert_equal "agent", user.role
    follow_redirect!
    assert_response :success

    get cases_path
    assert_response :success
  end

  test "staff oidc login reuses existing users by email" do
    mock_staff_oidc(email: users(:agent_a).email_address)
    assert_no_difference "User.count" do
      get "/auth/staff_oidc/callback"
    end
  end

  test "role mapping from idp claim promotes users" do
    Setting.set("sso_staff_role_claim", "groups")
    Setting.set("sso_staff_role_mapping", { "docket-admins" => "admin" }.to_json)
    mock_staff_oidc(email: "boss@example.com", groups: [ "everyone", "docket-admins" ])
    get "/auth/staff_oidc/callback"
    assert_equal "admin", User.find_by(email_address: "boss@example.com").role
  ensure
    Setting.unset("sso_staff_role_claim")
    Setting.unset("sso_staff_role_mapping")
  end

  test "deactivated users cannot enter via sso" do
    mock_staff_oidc(email: users(:inactive).email_address)
    get "/auth/staff_oidc/callback"
    assert_redirected_to new_session_path
    get cases_path
    assert_redirected_to new_session_path
  end

  test "staff saml login works" do
    OmniAuth.config.mock_auth[:staff_saml] = OmniAuth::AuthHash.new(
      provider: "staff_saml", uid: "samluser",
      info: { email: "samlstaff@example.com", name: "SAML Staff" }
    )
    post "/auth/staff_saml/callback"
    assert User.exists?(email_address: "samlstaff@example.com")
    get cases_path
    assert_response :success
  end

  test "customer oidc maps claim to contact external_id and opens the portal plane" do
    OmniAuth.config.mock_auth[:customer_oidc] = OmniAuth::AuthHash.new(
      provider: "customer_oidc", uid: "CIF777001",
      info: { email: "customer@example.com", name: "Bank Customer" },
      extra: { raw_info: {} }
    )
    assert_difference "Contact.count" do
      get "/auth/customer_oidc/callback"
    end
    contact = Contact.find_by(external_id: "CIF777001")
    assert contact.present?
    assert_redirected_to portal_my_cases_path

    # Customer can file and see their own cases without tracking IDs.
    post portal_my_cases_path, params: { case: { subject: "My netbanking issue", description: "Details here." } }
    kase = Case.order(:id).last
    assert_equal contact, kase.contact
    get portal_my_case_path(kase)
    assert_response :success
  end

  test "customer sessions can never reach the staff console" do
    OmniAuth.config.mock_auth[:customer_oidc] = OmniAuth::AuthHash.new(
      provider: "customer_oidc", uid: "CIF777002",
      info: { email: "cust2@example.com", name: "Customer Two" }, extra: { raw_info: {} }
    )
    get "/auth/customer_oidc/callback"
    get portal_my_cases_path
    assert_response :success

    # Staff plane: separate guard, separate cookie — must bounce.
    get cases_path
    assert_redirected_to new_session_path
    get admin_users_path
    assert_redirected_to new_session_path
  end

  test "customers cannot read other contacts cases in the portal" do
    OmniAuth.config.mock_auth[:customer_oidc] = OmniAuth::AuthHash.new(
      provider: "customer_oidc", uid: contacts(:ravi).external_id,
      info: { email: "x@example.com", name: "Ravi" }, extra: { raw_info: {} }
    )
    get "/auth/customer_oidc/callback"
    # asha's case must 404 for ravi
    get portal_my_case_path(cases(:pension_case))
    assert_response :not_found
  end

  test "staff sessions cannot act as portal customers" do
    sign_in_as users(:admin)
    get portal_my_cases_path
    assert_redirected_to portal_root_path
  end

  test "sso failure redirects with a friendly message" do
    OmniAuth.config.mock_auth[:staff_oidc] = :invalid_credentials
    get "/auth/staff_oidc/callback"
    follow_redirect! while response.redirect?
    assert_response :success
  end
end
