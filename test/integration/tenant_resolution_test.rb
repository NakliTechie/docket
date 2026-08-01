require "test_helper"

class TenantResolutionTest < ActionDispatch::IntegrationTest
  test "an isolated suspended tenant gets a branded HTML 503 and API error" do
    tenant = tenants(:primary)
    Setting.set("brand_name", "Northwind Support")
    tenant.suspended!

    get root_path
    assert_response :service_unavailable
    assert_includes response.body, "Northwind Support"
    assert_includes response.body, I18n.t("errors.tenant_suspended.title")

    get "/api/v1/cases", as: :json
    assert_response :service_unavailable
    assert_equal({ "error" => "tenant_suspended", "brand" => "Northwind Support" }, response.parsed_body)
  ensure
    tenant&.update_column(:status, Tenant.statuses.fetch("active"))
  end

  test "a suspended shared tenant is indistinguishable from an unknown host" do
    original = Rails.application.config.x.tenancy_mode
    Rails.application.config.x.tenancy_mode = "shared"
    tenant = tenants(:acme)
    tenant.suspended!
    host! "acme.docket.app"

    get root_path
    assert_response :not_found
  ensure
    tenant&.update_column(:status, Tenant.statuses.fetch("active"))
    Rails.application.config.x.tenancy_mode = original
  end

  test "the apex host is not assigned to a tenant in shared mode" do
    original = Rails.application.config.x.tenancy_mode
    Rails.application.config.x.tenancy_mode = "shared"
    host! "docket.app"

    get root_path
    assert_response :not_found
  ensure
    Rails.application.config.x.tenancy_mode = original
  end
end
