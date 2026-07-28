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
      @acme_contact = Contact.create!(name: "Acme Customer", email: "customer@acme.test")
      @acme_case = Case.create!(subject: "Acme-only ticket", channel: :web_portal,
                                priority: :normal, contact: @acme_contact)
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

  test "the public portal track lookup is scoped to the host's tenant" do
    host! "acme.docket.app"

    # acme's own case resolves with its contact's email.
    post portal_track_lookup_path, params: { tracking_id: @acme_case.tracking_id, contact_email: @acme_contact.email }
    assert_response :success
    assert_match "Acme-only ticket", response.body

    # A primary-tenant tracking id is invisible on the acme host (not just
    # email-mismatched — the case isn't in scope at all).
    primary = cases(:pension_case)
    post portal_track_lookup_path, params: { tracking_id: primary.tracking_id, contact_email: contacts(:asha).email }
    assert_response :unprocessable_entity
    refute_match primary.subject, response.body
  end

  test "an API token is scoped to its own tenant's host" do
    token = ActsAsTenant.with_tenant(@acme) { ApiToken.create!(user: @acme_user, name: "cli").raw_token }

    host! "acme.docket.app"
    get "/api/v1/cases", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
    assert_match "Acme-only ticket", response.body

    # The same token presented on a different tenant's host is rejected — its
    # user isn't in that tenant's scope.
    host! "nope.docket.app"
    get "/api/v1/cases", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :not_found # unknown subdomain resolves no tenant
  end

  # SharedCredential had no tenant_id and no acts_as_tenant — its policy Scope
  # returns `scope.all` and the controller does an unscoped find, so the console
  # listed every tenant's credentials at once.
  #
  # Scope note, so nobody over-reads this test: `connector:manage` is held by
  # super_admin ONLY (checked against Authz), and super_admin is the cross-tenant
  # platform tier. A tenant's own client_admin gets 403 here and never could reach
  # this surface. So this was defence-in-depth, not one customer reading another's
  # keys. It still matters — the platform console iterates tenants under
  # `with_tenant`, and this is what makes that iteration actually scope.
  test "shared credentials are scoped to the host's tenant" do
    primary_credential = ActsAsTenant.with_tenant(tenants(:primary)) do
      SharedCredential.create!(name: "primary_vault", label: "Primary Vault",
                               secrets_hash: { "api_key" => "PRIMARY-SECRET-KEY" })
    end
    acme_admin = ActsAsTenant.with_tenant(@acme) do
      User.create!(name: "Acme Platform", email_address: "platform@acme.test",
                   password: "password1234", role: :super_admin)
    end

    host! "acme.docket.app"
    sign_in_as acme_admin

    get admin_shared_credentials_path
    assert_response :success
    refute_match "Primary Vault", response.body
    refute_match "primary_vault", response.body

    # And not reachable by id either — the edit path did an unscoped find.
    get edit_admin_shared_credential_path(primary_credential)
    assert_response :not_found
  end

  # NOT COVERED HERE: `Connector validates_same_tenant :shared_credential`, added
  # alongside the tenant_id column so a connector cannot bind another tenant's
  # credential. It is verified working outside the suite — with two real tenants,
  # `Connector.new(shared_credential_id: <other tenant's>)` produces
  # `{:shared_credential=>[{:error=>:cross_tenant}]}` — but it will not reproduce
  # in this suite, because test_helper pins `ActsAsTenant.test_tenant` to :primary
  # for every test and that pin wins over with_tenant, a `tenant:` argument, and a
  # direct tenant_id assignment at validation time. Covering it properly means
  # giving the suite a way to run as a second tenant; until then this is a known
  # coverage hole, not a passing test pretending otherwise.
end
