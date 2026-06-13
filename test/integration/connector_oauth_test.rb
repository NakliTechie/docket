require "test_helper"

# The OAuth2 connect flow for OAuth connectors: an admin starts the connect
# (redirect to the vendor with signed state), the vendor redirects back, and we
# exchange the code for tokens + activate. State is tamper-checked; non-admins
# are refused.
class ConnectorOauthTest < ActionDispatch::IntegrationTest
  def gcal_connector
    c = Connector.create!(name: "GCal", provider: "google_calendar", config: { "client_id" => "cid.apps" })
    c.credentials_hash = { "client_secret" => "secret" }
    c.save!
    c
  end

  def valid_state(connector)
    Rails.application.message_verifier("connector_oauth").generate({ "cid" => connector.id }, expires_in: 15.minutes)
  end

  test "oauth_authorize redirects an admin to the vendor with state + scope" do
    sign_in_as users(:admin)
    c = gcal_connector
    get oauth_authorize_admin_connector_path(c)
    assert_response :redirect
    location = @response.headers["Location"]
    assert location.start_with?("https://accounts.google.com/o/oauth2/v2/auth?"), location
    assert_includes location, "state="
    assert_includes location, "scope="
  end

  test "oauth_authorize refuses until client credentials are present" do
    sign_in_as users(:admin)
    c = Connector.create!(name: "GCal2", provider: "google_calendar", config: { "client_id" => "cid" })
    # no client_secret → not configured
    get oauth_authorize_admin_connector_path(c)
    assert_redirected_to admin_connector_path(c)
    assert flash[:alert].present?
  end

  test "oauth_callback exchanges the code, stores tokens, and activates the connector" do
    sign_in_as users(:admin)
    c = gcal_connector
    stub_request(:post, "https://oauth2.googleapis.com/token")
      .to_return(status: 200,
                 body: { access_token: "ya29.x", refresh_token: "1//r", expires_in: 3600 }.to_json,
                 headers: { "Content-Type" => "application/json" })

    get oauth_callback_admin_connectors_path(code: "auth-code", state: valid_state(c))

    assert_redirected_to admin_connector_path(c)
    c.reload
    assert c.oauth_connected?
    assert c.status_active?
  end

  test "oauth_callback rejects a tampered or expired state" do
    sign_in_as users(:admin)
    get oauth_callback_admin_connectors_path(code: "x", state: "tampered.state.value")
    assert_redirected_to admin_connectors_path
    assert flash[:alert].present?
  end

  test "oauth_callback surfaces a provider-side denial" do
    sign_in_as users(:admin)
    c = gcal_connector
    get oauth_callback_admin_connectors_path(error: "access_denied", state: valid_state(c))
    assert_redirected_to admin_connector_path(c)
    assert flash[:alert].present?
    assert_not c.reload.oauth_connected?
  end

  test "a non-admin cannot start the OAuth connect" do
    sign_in_as users(:agent_a)
    c = gcal_connector
    get oauth_authorize_admin_connector_path(c)
    assert_response :forbidden
  end
end
