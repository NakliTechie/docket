require "test_helper"

class TenantUrlTest < ActiveSupport::TestCase
  test "shared tenants receive distinct public origins from one base deployment URL" do
    original_mode = Rails.application.config.x.tenancy_mode
    original_url = ENV["DOCKET_BASE_URL"]
    original_domain = ENV["DOCKET_BASE_DOMAIN"]
    Rails.application.config.x.tenancy_mode = "shared"
    ENV["DOCKET_BASE_URL"] = "https://docket.co.in"
    ENV["DOCKET_BASE_DOMAIN"] = "docket.co.in"

    ActsAsTenant.with_tenant(tenants(:acme)) do
      assert_equal "https://acme.docket.co.in", Docket::TenantUrl.base_url
      assert_equal "https://acme.docket.co.in", Sso.base_url
      assert_equal({ host: "acme.docket.co.in", protocol: "https" },
                   Docket::TenantUrl.options)
    end
  ensure
    Rails.application.config.x.tenancy_mode = original_mode
    ENV["DOCKET_BASE_URL"] = original_url
    ENV["DOCKET_BASE_DOMAIN"] = original_domain
  end
end
