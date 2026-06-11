require "test_helper"

module Api
  class AuthTest < ActionDispatch::IntegrationTest
    test "requests without a token are 401" do
      get "/api/v1/cases"
      assert_response :unauthorized
    end

    test "garbage tokens are 401" do
      get "/api/v1/cases", headers: auth_header("dkt_notreal")
      assert_response :unauthorized
      get "/api/v1/cases", headers: auth_header("dkts_notreal")
      assert_response :unauthorized
    end

    test "user tokens authenticate and update last_used_at" do
      token = ApiToken.create!(user: users(:admin), name: "t")
      get "/api/v1/cases", headers: auth_header(token.raw_token)
      assert_response :success
      assert token.reload.last_used_at.present?
    end

    test "revoked user tokens stop working" do
      token = ApiToken.create!(user: users(:admin), name: "t")
      token.revoke!
      get "/api/v1/cases", headers: auth_header(token.raw_token)
      assert_response :unauthorized
    end

    test "tokens of deactivated users stop working" do
      token = ApiToken.create!(user: users(:agent_a), name: "t")
      users(:agent_a).deactivate!
      get "/api/v1/cases", headers: auth_header(token.raw_token)
      assert_response :unauthorized
    end

    test "the bearer scheme is matched case-insensitively (L)" do
      token = ApiToken.create!(user: users(:admin), name: "t").raw_token
      get "/api/v1/cases", headers: { "Authorization" => "bearer #{token}" }
      assert_response :success
    end

    test "token responses are marked no-store (L, RFC 6749)" do
      account = ServiceAccount.create!(name: "No Store", scopes: %w[cases:read])
      post "/api/v1/oauth/token", params: {
        grant_type: "client_credentials",
        client_id: account.client_id, client_secret: account.raw_client_secret
      }
      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
    end

    test "client credentials grant issues scoped bearer" do
      account = ServiceAccount.create!(name: "Grant Test", scopes: %w[cases:read])
      post "/api/v1/oauth/token", params: {
        grant_type: "client_credentials",
        client_id: account.client_id, client_secret: account.raw_client_secret
      }
      assert_response :success
      body = response.parsed_body
      assert body["access_token"].start_with?("dkts_")
      assert_equal "cases:read", body["scope"]

      get "/api/v1/cases", headers: auth_header(body["access_token"])
      assert_response :success
    end

    test "wrong client secret is rejected" do
      account = ServiceAccount.create!(name: "Wrong Secret", scopes: %w[cases:read])
      post "/api/v1/oauth/token", params: {
        grant_type: "client_credentials",
        client_id: account.client_id, client_secret: "wrong"
      }
      assert_response :unauthorized
    end

    test "http basic client auth works" do
      account = ServiceAccount.create!(name: "Basic Test", scopes: %w[cases:read])
      basic = Base64.strict_encode64("#{account.client_id}:#{account.raw_client_secret}")
      post "/api/v1/oauth/token", params: { grant_type: "client_credentials" },
           headers: { "Authorization" => "Basic #{basic}" }
      assert_response :success
    end

    test "expired access tokens stop working" do
      token = service_token_for(%w[cases:read])
      OauthAccessToken.find_by(token_digest: OauthAccessToken.digest(token))
                      .update_columns(expires_at: 1.minute.ago)
      get "/api/v1/cases", headers: auth_header(token)
      assert_response :unauthorized
    end

    test "deactivating a service account kills its live tokens" do
      account = ServiceAccount.create!(name: "Deactivate Test", scopes: %w[cases:read])
      raw = account.issue_access_token!.raw_token
      account.deactivate!
      get "/api/v1/cases", headers: auth_header(raw)
      assert_response :unauthorized
    end

    test "secret rotation revokes live tokens" do
      account = ServiceAccount.create!(name: "Rotate Test", scopes: %w[cases:read])
      raw = account.issue_access_token!.raw_token
      new_secret = account.rotate_secret!
      get "/api/v1/cases", headers: auth_header(raw)
      assert_response :unauthorized
      assert ServiceAccount.authenticate(account.client_id, new_secret)
    end
  end
end
