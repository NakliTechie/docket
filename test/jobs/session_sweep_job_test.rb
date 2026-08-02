require "test_helper"

class SessionSweepJobTest < ActiveSupport::TestCase
  test "purges sessions past their TTL but keeps live ones (M5)" do
    user = users(:admin)
    live = user.sessions.create!(user_agent: "x", ip_address: "127.0.0.1")
    idle = user.sessions.create!(user_agent: "x", ip_address: "127.0.0.1")
    idle.update_columns(updated_at: (Session::IDLE_TIMEOUT + 1.hour).ago)
    old = user.sessions.create!(user_agent: "x", ip_address: "127.0.0.1")
    old.update_columns(created_at: (Session::ABSOLUTE_TIMEOUT + 1.day).ago)

    SessionSweepJob.perform_now

    assert Session.exists?(live.id)
    assert_not Session.exists?(idle.id)
    assert_not Session.exists?(old.id)
  end

  test "purges expired oauth access tokens but keeps live ones (L)" do
    account = ServiceAccount.create!(name: "Sweep", scopes: %w[cases:read])
    live = account.issue_access_token!
    expired = account.issue_access_token!
    expired.update_columns(expires_at: 1.minute.ago)

    assert_difference "OauthAccessToken.count", -1 do
      SessionSweepJob.perform_now
    end
    assert OauthAccessToken.exists?(live.id)
    assert_not OauthAccessToken.exists?(expired.id)
  end

  test "purges expired OAuth codes and refresh tokens" do
    client = OauthClient.create!(tenant: tenants(:primary), client_name: "Sweep client",
                                 redirect_uris: [ "https://client.example/callback" ],
                                 grant_types: %w[authorization_code refresh_token], response_types: [ "code" ],
                                 token_endpoint_auth_method: "none")
    code = OauthAuthorizationCode.issue!(oauth_client: client, user: users(:admin),
                                          redirect_uri: client.redirect_uris.first,
                                          code_challenge: "a" * 43, scopes: %w[cases:read],
                                          resource: Oauth::Metadata.resource)
    refresh = OauthRefreshToken.issue!(oauth_client: client, user: users(:admin), scopes: %w[cases:read],
                                       resource: Oauth::Metadata.resource)
    code.update_columns(expires_at: 1.minute.ago)
    refresh.update_columns(expires_at: 1.minute.ago)

    SessionSweepJob.perform_now

    assert_not OauthAuthorizationCode.exists?(code.id)
    assert_not OauthRefreshToken.exists?(refresh.id)
  end
end
