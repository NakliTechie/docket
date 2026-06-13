require "test_helper"

# Exercises the SHARED deployment topology (dormant by default): tenant resolved
# from the subdomain, data isolated per host. Flips the mode per-test.
class SharedModeTenancyTest < ActionDispatch::IntegrationTest
  setup do
    @orig_mode = Rails.application.config.x.tenancy_mode
    Rails.application.config.x.tenancy_mode = "shared"
    @acme = tenants(:acme)
    ActsAsTenant.with_tenant(@acme) do
      @acme_user = User.create!(name: "Acme Admin", email_address: "admin@acme.test",
                                password: "password1234", role: :client_admin)
      contact = Contact.create!(name: "Acme Customer", email: "customer@acme.test")
      @acme_case = Case.create!(subject: "Acme-only ticket", channel: :web_portal,
                                priority: :normal, contact: contact)
    end
  end

  teardown { Rails.application.config.x.tenancy_mode = @orig_mode }

  test "an unknown subdomain is 404 before authentication" do
    host! "nope.docket.app"
    get cases_path
    assert_response :not_found
  end

  test "a tenant subdomain scopes the signed-in user to its own data" do
    host! "acme.docket.app"
    sign_in_as @acme_user

    get cases_path
    assert_response :success
    assert_match "Acme-only ticket", response.body
    # Primary tenant's fixture case must not be visible on the acme host.
    refute_match cases(:pension_case).subject, response.body
  end
end
