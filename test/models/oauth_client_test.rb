require "test_helper"

class OauthClientTest < ActiveSupport::TestCase
  def attributes(**overrides)
    {
      tenant: tenants(:primary), client_name: "MCP test client",
      redirect_uris: [ "https://client.example/callback" ],
      grant_types: %w[authorization_code refresh_token], response_types: %w[code],
      token_endpoint_auth_method: "none"
    }.merge(overrides)
  end

  test "public and confidential clients generate the correct credentials" do
    public_client = OauthClient.create!(attributes)
    assert public_client.client_id.start_with?("mcp_")
    assert_nil public_client.raw_client_secret
    assert public_client.authenticate_secret(nil)

    confidential = OauthClient.create!(attributes(token_endpoint_auth_method: "client_secret_basic"))
    assert confidential.raw_client_secret.present?
    assert confidential.authenticate_secret(confidential.raw_client_secret)
    assert_not confidential.authenticate_secret("wrong")
  end

  test "redirect URIs require HTTPS except for loopback clients" do
    assert OauthClient.new(attributes(redirect_uris: [ "http://127.0.0.1:49152/callback" ])).valid?
    assert OauthClient.new(attributes(redirect_uris: [ "http://localhost:3000/callback" ])).valid?
    assert OauthClient.new(attributes(redirect_uris: [ "http://[::1]:3000/callback" ])).valid?
    assert_not OauthClient.new(attributes(redirect_uris: [ "http://client.example/callback" ])).valid?
    assert_not OauthClient.new(attributes(redirect_uris: [ "https://client.example/callback#fragment" ])).valid?
    assert_not OauthClient.new(attributes(redirect_uris: [ "https://user@client.example/callback" ])).valid?
    assert_not OauthClient.new(attributes(redirect_uris: [ "https://*.example.com/callback" ])).valid?
  end

  test "deactivation revokes every client authorization artifact" do
    client = OauthClient.create!(attributes)
    user = users(:admin)
    code = OauthAuthorizationCode.issue!(oauth_client: client, user: user,
                                          redirect_uri: client.redirect_uris.first,
                                          code_challenge: "a" * 43, scopes: %w[cases:read],
                                          resource: Oauth::Metadata.resource)
    access = OauthAccessToken.issue!(user: user, oauth_client: client, scopes: %w[cases:read],
                                     resource: Oauth::Metadata.resource)
    refresh = OauthRefreshToken.issue!(oauth_client: client, user: user, scopes: %w[cases:read],
                                       resource: Oauth::Metadata.resource)

    client.deactivate!

    assert_not OauthAuthorizationCode.exists?(code.id)
    assert_not OauthAccessToken.exists?(access.id)
    assert_not OauthRefreshToken.exists?(refresh.id)
  end

  test "staff deactivation removes browser and OAuth authorization artifacts" do
    client = OauthClient.create!(attributes)
    user = users(:agent_a)
    session = user.sessions.create!
    code = OauthAuthorizationCode.issue!(oauth_client: client, user: user,
                                          redirect_uri: client.redirect_uris.first,
                                          code_challenge: "a" * 43, scopes: %w[cases:read],
                                          resource: Oauth::Metadata.resource)
    access = OauthAccessToken.issue!(user: user, oauth_client: client, scopes: %w[cases:read],
                                     resource: Oauth::Metadata.resource)
    refresh = OauthRefreshToken.issue!(oauth_client: client, user: user, scopes: %w[cases:read],
                                       resource: Oauth::Metadata.resource)

    user.deactivate!

    assert_not Session.exists?(session.id)
    assert_not OauthAuthorizationCode.exists?(code.id)
    assert_not OauthAccessToken.exists?(access.id)
    assert_not OauthRefreshToken.exists?(refresh.id)
  end
end
