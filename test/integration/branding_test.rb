require "test_helper"

# The product reads private-first: a neutral default brand + neutral
# vocabulary, with the brand configurable per deploy (gov is a special case).
class BrandingTest < ActionDispatch::IntegrationTest
  test "the brand defaults to the product name in the staff header" do
    sign_in_as users(:admin)
    get root_path
    follow_redirect! # root is an entitlement-aware redirector since ENT
    assert_response :success
    assert_match "Docket", response.body
  end

  test "an admin sets a custom brand and it shows in the header and the portal" do
    Setting.set("brand_name", "Acme Support")
    sign_in_as users(:admin)
    get admin_settings_path
    assert_match "Acme Support", response.body

    reset! # anonymous
    get "/portal"
    assert_response :success
    assert_match "Acme Support", response.body
  end

  test "settings accepts the brand_name" do
    sign_in_as users(:admin)
    patch admin_settings_path, params: { brand_name: "Globex" }
    assert_equal "Globex", Setting.get("brand_name")
  end

  test "the customer portal reads private-first — no grievance language" do
    get "/portal"
    assert_response :success
    assert_no_match(/grievance/i, response.body)
    assert_match "Submit a request", response.body
  end

  test "browser layouts advertise the shipped icons" do
    get "/portal"
    assert_response :success
    assert_select 'link[rel="icon"][href="/icon.svg"][type="image/svg+xml"]'
    assert_select 'link[rel="icon"][href="/icon.png"][type="image/png"]'

    get "/inquiry"
    assert_response :success
    assert_select 'link[rel="icon"][href="/icon.svg"][type="image/svg+xml"]'
    assert_select 'link[rel="icon"][href="/icon.png"][type="image/png"]'

    sign_in_as users(:admin)
    get cases_path
    assert_response :success
    assert_select 'link[rel="icon"][href="/icon.svg"][type="image/svg+xml"]'
    assert_select 'link[rel="icon"][href="/icon.png"][type="image/png"]'
  end

  test "public layouts publish concise page descriptions" do
    get portal_root_path
    assert_select 'meta[name="description"][content*="Submit and track"]'

    get inquiry_path
    assert_select 'meta[name="description"][content*="request more information"]'

    get new_session_path
    assert_select 'meta[name="description"][content*="Sign in"]'
    assert_select "a[href='#{portal_root_path}']", text: I18n.t("sessions.new.customer_portal")

    get portal_root_path
    assert_select "a[href='#{new_session_path}']", text: I18n.t("portal.nav.staff_sign_in")
  end

  test "the CSP nonce covers Turbo's progress stylesheet" do
    get portal_root_path
    policy = response.headers["Content-Security-Policy"]
    nonce = css_select('meta[name="csp-nonce"]').first["content"]

    assert_includes policy, "style-src 'self' 'nonce-#{nonce}'"
  end
end
