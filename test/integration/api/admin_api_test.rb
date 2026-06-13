require "test_helper"

module Api
  class AdminApiTest < ActionDispatch::IntegrationTest
    setup do
      @admin_token = api_token_for(users(:admin))
    end

    test "users management is admin-human-only" do
      get "/api/v1/users", headers: auth_header(@admin_token)
      assert_response :success

      post "/api/v1/users", params: { user: { name: "API User", email_address: "apiuser@example.com",
                                              password: "longpassword1", role: "agent" } },
           headers: auth_header(@admin_token), as: :json
      assert_response :created

      sa_token = service_token_for(ServiceAccount::SCOPES)
      get "/api/v1/users", headers: auth_header(sa_token)
      assert_response :forbidden

      agent_token = api_token_for(users(:agent_a))
      get "/api/v1/users", headers: auth_header(agent_token)
      assert_response :forbidden
    end

    test "api token lifecycle over the api" do
      post "/api/v1/api_tokens", params: { api_token: { user_id: users(:agent_a).id, name: "cli" } },
           headers: auth_header(@admin_token), as: :json
      assert_response :created
      raw = response.parsed_body["data"]["token"]
      assert raw.start_with?("dkt_")

      delete "/api/v1/api_tokens/#{response.parsed_body["data"]["id"]}", headers: auth_header(@admin_token)
      assert_response :no_content
      get "/api/v1/cases", headers: auth_header(raw)
      assert_response :unauthorized
    end

    test "service account lifecycle over the api" do
      post "/api/v1/service_accounts", params: {
        service_account: { name: "API SA", scopes: [ "cases:read" ] }
      }, headers: auth_header(@admin_token), as: :json
      assert_response :created
      body = response.parsed_body["data"]
      assert body["client_secret"].present?

      post "/api/v1/service_accounts/#{body["id"]}/rotate_secret", headers: auth_header(@admin_token)
      assert_response :success
      refute_equal body["client_secret"], response.parsed_body["data"]["client_secret"]

      sa_token = service_token_for(ServiceAccount::SCOPES)
      post "/api/v1/service_accounts", params: { service_account: { name: "Sneaky", scopes: [ "cases:read" ] } },
           headers: auth_header(sa_token), as: :json
      assert_response :forbidden
    end

    test "settings read masks secrets and write works" do
      Setting.set("llm_api_key", "supersecret")
      Setting.set("sso_staff_oidc_client_secret", "oidc-staff-secret")
      Setting.set("sso_customer_oidc_client_secret", "oidc-customer-secret")
      get "/api/v1/settings", headers: auth_header(@admin_token)
      assert_response :success
      assert_equal "[SET]", response.parsed_body["data"]["llm_api_key"]
      # Every secret is masked, not just the LLM key (H1).
      assert_equal "[SET]", response.parsed_body["data"]["sso_staff_oidc_client_secret"]
      assert_equal "[SET]", response.parsed_body["data"]["sso_customer_oidc_client_secret"]
      refute_includes response.body, "supersecret"
      refute_includes response.body, "oidc-staff-secret"
      refute_includes response.body, "oidc-customer-secret"

      patch "/api/v1/settings", params: { llm_provider: "fake" },
            headers: auth_header(@admin_token), as: :json
      assert_equal "fake", Setting.get("llm_provider")

      # Writing the mask back (read-modify-write) must not corrupt or wipe
      # the stored secrets.
      patch "/api/v1/settings",
            params: { sso_staff_oidc_client_secret: "[SET]", sso_customer_oidc_client_secret: "" },
            headers: auth_header(@admin_token), as: :json
      assert_equal "oidc-staff-secret", Setting.get("sso_staff_oidc_client_secret")
      assert_equal "oidc-customer-secret", Setting.get("sso_customer_oidc_client_secret")

      config_token = service_token_for(%w[config:read])
      get "/api/v1/settings", headers: auth_header(config_token)
      assert_response :success
      patch "/api/v1/settings", params: { llm_provider: "off" },
            headers: auth_header(config_token), as: :json
      assert_response :forbidden
    end

    test "audit endpoints serve entries and verification" do
      Contact.create!(name: "Audit Subject", email: "audit-api@example.com")
      get "/api/v1/audit/entries", params: { auditable_type: "Contact" }, headers: auth_header(@admin_token)
      assert_response :success
      assert response.parsed_body["data"].any?

      get "/api/v1/audit/verification", headers: auth_header(@admin_token)
      assert response.parsed_body["data"]["ok"]

      audit_token = service_token_for(%w[audit:read])
      get "/api/v1/audit/verification", headers: auth_header(audit_token)
      assert_response :success

      cases_token = service_token_for(%w[cases:read])
      get "/api/v1/audit/entries", headers: auth_header(cases_token)
      assert_response :forbidden
    end

    test "webhook endpoints manageable by admin and webhooks:manage" do
      post "/api/v1/webhook_endpoints", params: {
        webhook_endpoint: { name: "CRM", url: "https://crm.example.in/hook", events: [ "case.created" ] }
      }, headers: auth_header(@admin_token), as: :json
      assert_response :created
      assert response.parsed_body["data"]["secret"].start_with?("whsec_")
      id = response.parsed_body["data"]["id"]

      get "/api/v1/webhook_endpoints/#{id}/deliveries", headers: auth_header(@admin_token)
      assert_response :success

      hooks_token = service_token_for(%w[webhooks:manage])
      get "/api/v1/webhook_endpoints", headers: auth_header(hooks_token)
      assert_response :success

      cases_token = service_token_for(%w[cases:read])
      get "/api/v1/webhook_endpoints", headers: auth_header(cases_token)
      assert_response :forbidden
    end

    # Regression: these endpoints gate human tokens via the matrix (can?), not a
    # bare role_admin? — so the functional super_admin role reaches them and a
    # non-privileged functional role (finance) is refused.
    test "functional super_admin token reaches the admin endpoints" do
      token = api_token_for(users(:super_admin))
      [ "/api/v1/users", "/api/v1/settings", "/api/v1/service_accounts",
        "/api/v1/api_tokens", "/api/v1/webhook_endpoints",
        "/api/v1/audit/verification", "/api/v1/reports/activity" ].each do |path|
        get path, headers: auth_header(token)
        assert_response :success, "super_admin should reach #{path}"
      end
    end

    test "a finance token is refused the platform/admin endpoints" do
      token = api_token_for(users(:finance))
      [ "/api/v1/settings", "/api/v1/service_accounts", "/api/v1/api_tokens",
        "/api/v1/webhook_endpoints" ].each do |path|
        get path, headers: auth_header(token)
        assert_response :forbidden, "finance should be refused #{path}"
      end
    end
  end
end
