require "test_helper"

# Covers the admin-area mutation surfaces that AdminAreaPolicy authorizes.
# These had NO test coverage, which is why C1 (the policy defined only
# show?/index?, so every write 403'd or 500'd) shipped. Also pins the
# bugs that C1 was masking: secret-preservation on settings save (H4),
# boolean checkboxes that can be turned off (H5), and scope/event
# checkboxes that can be cleared to a validation error rather than a
# silent no-op (H6).
class AdminManagementTest < ActionDispatch::IntegrationTest
  # --- C1: every admin mutation surface works for admins -----------------

  test "admin can update settings (settings#update no longer 403s)" do
    sign_in_as users(:admin)
    patch admin_settings_path, params: { llm_model: "llama3" }
    assert_redirected_to admin_settings_path
    assert_equal "llama3", Setting.get("llm_model")
  end

  test "admin can create, rotate, and destroy a service account" do
    sign_in_as users(:admin)

    assert_difference -> { ServiceAccount.count }, 1 do
      post admin_service_accounts_path, params: {
        service_account: { name: "CRM", scopes: [ "cases:read", "cases:write" ] }
      }
    end
    assert_redirected_to admin_service_accounts_path
    account = ServiceAccount.order(:id).last

    post rotate_secret_admin_service_account_path(account)
    assert_redirected_to admin_service_accounts_path

    delete admin_service_account_path(account)
    assert_redirected_to admin_service_accounts_path
    assert_not ServiceAccount.exists?(account.id)
  end

  test "admin can create, view deliveries for, and destroy a webhook endpoint" do
    sign_in_as users(:admin)

    assert_difference -> { WebhookEndpoint.count }, 1 do
      post admin_webhook_endpoints_path, params: {
        webhook_endpoint: { name: "CRM hook", url: "https://crm.example.in/hooks", events: [ "case.created" ] }
      }
    end
    endpoint = WebhookEndpoint.order(:id).last

    get deliveries_admin_webhook_endpoint_path(endpoint)
    assert_response :success

    delete admin_webhook_endpoint_path(endpoint)
    assert_not WebhookEndpoint.exists?(endpoint.id)
  end

  test "admin can issue and revoke an api token" do
    sign_in_as users(:admin)
    assert_difference -> { ApiToken.count }, 1 do
      post admin_api_tokens_path, params: { api_token: { user_id: users(:admin).id, name: "tooling" } }
    end
  end

  test "non-admins are forbidden from admin mutation surfaces" do
    sign_in_as users(:supervisor)
    patch admin_settings_path, params: { llm_model: "x" }
    assert_response :forbidden
    post admin_service_accounts_path, params: { service_account: { name: "x", scopes: [ "cases:read" ] } }
    assert_response :forbidden
    post admin_webhook_endpoints_path, params: {
      webhook_endpoint: { name: "x", url: "https://x.example", events: [ "case.created" ] }
    }
    assert_response :forbidden
  end

  # --- H4: saving the settings form must not wipe stored secrets ---------

  test "saving settings with a blank secret field leaves the stored secret intact" do
    Setting.set("llm_api_key", "sk-keep-me")
    Setting.set("sso_staff_oidc_client_secret", "oidc-keep-me")
    sign_in_as users(:admin)

    # A normal save submits empty password fields (never echoed back).
    patch admin_settings_path, params: { llm_model: "llama3", llm_api_key: "", sso_staff_oidc_client_secret: "" }

    assert_equal "sk-keep-me", Setting.get("llm_api_key")
    assert_equal "oidc-keep-me", Setting.get("sso_staff_oidc_client_secret")
  end

  test "a non-blank secret submission updates the secret" do
    Setting.set("llm_api_key", "sk-old")
    sign_in_as users(:admin)
    patch admin_settings_path, params: { llm_api_key: "sk-new" }
    assert_equal "sk-new", Setting.get("llm_api_key")
  end

  # --- H5: boolean settings can be turned OFF ----------------------------

  test "unchecking a boolean setting turns it off (hidden 0 companion)" do
    Setting.set("llm_byok_enabled", true)
    sign_in_as users(:admin)

    # Unchecked box submits only the hidden "0".
    patch admin_settings_path, params: { llm_byok_enabled: "0" }
    assert_equal false, Setting.get("llm_byok_enabled")

    # Checked box: browser sends "0" then "1"; last wins.
    patch admin_settings_path, params: { llm_byok_enabled: "1" }
    assert_equal true, Setting.get("llm_byok_enabled")
  end

  # --- M34: settings coercion is hardened --------------------------------

  test "settings update ignores param-pollution shapes instead of 500ing" do
    sign_in_as users(:admin)
    patch admin_settings_path, params: { llm_model: { evil: "1" }, ai_route_confidence: "0.5" }
    assert_redirected_to admin_settings_path
    assert_equal 0.5, Setting.get("ai_route_confidence")
  end

  test "confidence thresholds are clamped to 0..1" do
    sign_in_as users(:admin)
    patch admin_settings_path, params: { ai_resolve_confidence: "5", ai_route_confidence: "-2" }
    assert_equal 1.0, Setting.get("ai_resolve_confidence")
    assert_equal 0.0, Setting.get("ai_route_confidence")
  end

  # --- H6: scope / event checkboxes can be cleared (to a validation error) ---

  test "clearing all scopes on a service account surfaces a validation error, not a silent no-op" do
    sign_in_as users(:admin)
    account = ServiceAccount.create!(name: "Keep", scopes: [ "cases:read" ])

    # All boxes unchecked => only the empty-string companion submits.
    patch admin_service_account_path(account), params: {
      service_account: { name: "Keep", scopes: [ "" ] }
    }
    assert_response :unprocessable_entity
    assert_equal [ "cases:read" ], account.reload.scopes # unchanged, not wiped
  end

  test "clearing all events on a webhook endpoint surfaces a validation error" do
    sign_in_as users(:admin)
    endpoint = WebhookEndpoint.create!(name: "Keep", url: "https://x.example/h", events: [ "case.created" ])
    patch admin_webhook_endpoint_path(endpoint), params: {
      webhook_endpoint: { name: "Keep", url: "https://x.example/h", events: [ "" ] }
    }
    assert_response :unprocessable_entity
    assert_equal [ "case.created" ], endpoint.reload.events
  end
end
