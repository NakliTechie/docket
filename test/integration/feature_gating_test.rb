require "test_helper"

# Proves the entitlement guard actually bites. The unit side (registry,
# resolution, Authz intersection) is test/models/features_test.rb; this is the
# request-level contract: a module a tenant doesn't have is NOT REACHABLE, by
# any route, for any role.
class FeatureGatingTest < ActionDispatch::IntegrationTest
  def disable!(key)
    ActsAsTenant.current_tenant.set_feature!(key, false)
  end

  test "with CRM off, its console surfaces 404 — not 403" do
    disable!("crm")
    sign_in_as users(:admin) # super_admin: role authority is not the limit here

    [ leads_path, deals_path, pipelines_path ].each do |path|
      get path
      assert_response :not_found, "#{path} should not exist for a tenant without CRM"
    end
  end

  test "with CRM on, the same surfaces are reachable (the guard is not blanket-denying)" do
    sign_in_as users(:admin)

    get leads_path
    assert_response :success
  end

  test "disabling a module takes its sub-features with it" do
    disable!("crm")
    sign_in_as users(:admin)

    get sequences_path
    assert_response :not_found, "crm.sequences must die with crm"
  end

  test "a sub-feature can be off while its module stays reachable" do
    disable!("crm.sequences")
    sign_in_as users(:admin)

    get sequences_path
    assert_response :not_found

    get leads_path
    assert_response :success, "the module itself is untouched"
  end

  test "the API answers 403 feature_disabled so an integrator can diagnose it" do
    disable!("crm")
    token = api_token_for(users(:admin))

    get api_v1_leads_path, headers: auth_header(token)
    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "feature_disabled", body["error"]
    assert_equal "crm", body["detail"]
  end

  test "service desk off closes the console, the API and the public portal" do
    disable!("service_desk")
    sign_in_as users(:admin)

    get cases_path
    assert_response :not_found
  end

  test "the public portal is gated independently of the desk it fronts" do
    disable!("service_desk.portal")

    get portal_root_path
    assert_response :not_found
  end

  test "an unaffected module keeps working while another is off" do
    disable!("crm")
    sign_in_as users(:admin)

    get cases_path
    assert_response :success
  end

  test "entitlements are per tenant, not per deployment" do
    tenants(:acme).set_feature!("crm", false)
    sign_in_as users(:admin) # primary tenant, CRM untouched

    get leads_path
    assert_response :success
    refute tenants(:acme).feature?("crm")
    assert tenants(:primary).feature?("crm")
  end
end
