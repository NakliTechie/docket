require "test_helper"

class OauthAuthorizationTest < ActionDispatch::IntegrationTest
  REDIRECT_URI = "https://client.example/callback".freeze

  setup do
    @verifier = "v" * 43
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
  end

  test "metadata advertises discovery, PKCE, registration, refresh, and the MCP resource" do
    get "/.well-known/oauth-protected-resource/api/v1/mcp"
    assert_response :success
    protected_resource = response.parsed_body
    assert_equal Oauth::Metadata.resource, protected_resource["resource"]
    assert_equal [ Oauth::Metadata.issuer ], protected_resource["authorization_servers"]

    get "/.well-known/oauth-authorization-server"
    assert_response :success
    metadata = response.parsed_body
    assert_equal [ "S256" ], metadata["code_challenge_methods_supported"]
    assert_includes metadata["grant_types_supported"], "authorization_code"
    assert_includes metadata["grant_types_supported"], "refresh_token"
    assert_includes metadata["scopes_supported"], "offline_access"
    assert_equal "#{Oauth::Metadata.issuer}/oauth/register", metadata["registration_endpoint"]
  end

  test "unauthenticated MCP requests return an RFC 9728 discovery challenge" do
    post "/api/v1/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :unauthorized
    challenge = response.headers["WWW-Authenticate"]
    assert_includes challenge, "Bearer"
    assert_includes challenge, "resource_metadata=\"#{Oauth::Metadata.protected_resource_url}\""
    assert_includes challenge, "offline_access"
  end

  test "dynamic registration accepts HTTPS and public PKCE clients" do
    assert_difference -> { OauthClient.count }, 1 do
      post "/oauth/register", params: {
        client_name: "Claude", redirect_uris: [ REDIRECT_URI ],
        grant_types: %w[authorization_code refresh_token], response_types: [ "code" ],
        token_endpoint_auth_method: "none"
      }, as: :json
    end

    assert_response :created
    body = response.parsed_body
    assert body["client_id"].start_with?("mcp_")
    assert_nil body["client_secret"]
    assert_equal "none", body["token_endpoint_auth_method"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "dynamic registration rejects insecure remote redirects" do
    post "/oauth/register", params: {
      client_name: "Unsafe", redirect_uris: [ "http://client.example/callback" ],
      grant_types: [ "authorization_code" ], response_types: [ "code" ],
      token_endpoint_auth_method: "none"
    }, as: :json

    assert_response :bad_request
    assert_equal "invalid_client_metadata", response.parsed_body["error"]
  end

  test "confidential dynamic clients authenticate the code exchange with HTTP Basic" do
    post "/oauth/register", params: {
      client_name: "Confidential client", redirect_uris: [ REDIRECT_URI ],
      grant_types: %w[authorization_code refresh_token], response_types: [ "code" ],
      token_endpoint_auth_method: "client_secret_basic"
    }, as: :json
    assert_response :created
    registration = response.parsed_body
    client = OauthClient.find_by!(client_id: registration.fetch("client_id"))
    code = authorize(client, scopes: %w[cases:read])
    basic = Base64.strict_encode64("#{client.client_id}:#{registration.fetch('client_secret')}")

    post "/oauth/token", params: {
      grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI,
      code_verifier: @verifier, resource: Oauth::Metadata.resource
    }, headers: { "Authorization" => "Basic #{basic}" }

    assert_response :success
    assert response.parsed_body["access_token"].start_with?("dkts_")
  end

  test "authorization code with PKCE issues a user token and rotates refresh tokens" do
    client = create_client
    code = authorize(client, scopes: %w[cases:read offline_access])

    post "/oauth/token", params: {
      grant_type: "authorization_code", client_id: client.client_id,
      code: code, redirect_uri: REDIRECT_URI, code_verifier: @verifier,
      resource: Oauth::Metadata.resource
    }
    assert_response :success
    issued = response.parsed_body
    assert issued["access_token"].start_with?("dkts_")
    assert issued["refresh_token"].start_with?("dktr_")
    assert_equal "cases:read offline_access", issued["scope"]

    get "/api/v1/cases", headers: auth_header(issued["access_token"])
    assert_response :success
    kase = cases(:pension_case)
    patch "/api/v1/cases/#{kase.id}", params: { case: { subject: "Not allowed" } },
          headers: auth_header(issued["access_token"])
    assert_response :forbidden

    post "/oauth/token", params: {
      grant_type: "refresh_token", client_id: client.client_id,
      refresh_token: issued["refresh_token"], resource: Oauth::Metadata.resource
    }
    assert_response :success
    rotated = response.parsed_body
    assert_not_equal issued["refresh_token"], rotated["refresh_token"]

    post "/oauth/token", params: {
      grant_type: "refresh_token", client_id: client.client_id,
      refresh_token: issued["refresh_token"], resource: Oauth::Metadata.resource
    }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "authorization codes are single-use and bound to PKCE, redirect URI, client, and resource" do
    client = create_client
    code = authorize(client, scopes: %w[cases:read])
    other_client = OauthClient.create!(
      tenant: tenants(:primary), client_name: "Other client", redirect_uris: [ REDIRECT_URI ],
      grant_types: %w[authorization_code refresh_token], response_types: [ "code" ],
      token_endpoint_auth_method: "none"
    )

    post "/oauth/token", params: {
      grant_type: "authorization_code", client_id: other_client.client_id,
      code: code, redirect_uri: REDIRECT_URI, code_verifier: @verifier,
      resource: Oauth::Metadata.resource
    }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", client_id: client.client_id,
      code: code, redirect_uri: "https://client.example/other", code_verifier: @verifier,
      resource: Oauth::Metadata.resource
    }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", client_id: client.client_id,
      code: code, redirect_uri: REDIRECT_URI, code_verifier: "x" * 43,
      resource: Oauth::Metadata.resource
    }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", client_id: client.client_id,
      code: code, redirect_uri: REDIRECT_URI, code_verifier: @verifier,
      resource: "https://other.example/mcp"
    }
    assert_response :bad_request
    assert_equal "invalid_target", response.parsed_body["error"]

    post "/oauth/token", params: {
      grant_type: "authorization_code", client_id: client.client_id,
      code: code, redirect_uri: REDIRECT_URI, code_verifier: @verifier,
      resource: Oauth::Metadata.resource
    }
    assert_response :success

    post "/oauth/token", params: {
      grant_type: "authorization_code", client_id: client.client_id,
      code: code, redirect_uri: REDIRECT_URI, code_verifier: @verifier,
      resource: Oauth::Metadata.resource
    }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "denial returns an OAuth error without issuing a code" do
    client = create_client
    sign_in_as users(:admin)
    get_authorization(client)
    request_token = Nokogiri::HTML(response.body).at_css("input[name=request_token]")["value"]

    assert_no_difference -> { OauthAuthorizationCode.count } do
      post "/oauth/authorize", params: { request_token: request_token, decision: "deny" }
    end
    assert_response :redirect
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    assert_equal "access_denied", query["error"]
    assert_equal "opaque-state", query["state"]
  end

  test "OAuth scopes and the staff role must both authorize a mutation" do
    client = create_client
    code = authorize(client, scopes: %w[cases:write], user: users(:readonly))
    post "/oauth/token", params: {
      grant_type: "authorization_code", client_id: client.client_id,
      code: code, redirect_uri: REDIRECT_URI, code_verifier: @verifier,
      resource: Oauth::Metadata.resource
    }
    token = response.parsed_body.fetch("access_token")

    patch "/api/v1/cases/#{cases(:pension_case).id}",
          params: { case: { subject: "Forbidden role write" } }, headers: auth_header(token)
    assert_response :forbidden
  end

  private

  def create_client
    OauthClient.create!(
      tenant: tenants(:primary), client_name: "Test MCP client", redirect_uris: [ REDIRECT_URI ],
      grant_types: %w[authorization_code refresh_token], response_types: [ "code" ],
      token_endpoint_auth_method: "none"
    )
  end

  def authorize(client, scopes:, user: users(:admin))
    sign_in_as user
    get_authorization(client, scopes: scopes)
    assert_response :success
    request_token = Nokogiri::HTML(response.body).at_css("input[name=request_token]")["value"]
    post "/oauth/authorize", params: {
      request_token: request_token, decision: "allow", scopes: scopes
    }
    assert_response :redirect
    Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
  end

  def get_authorization(client, scopes: %w[cases:read offline_access])
    get "/oauth/authorize", params: {
      response_type: "code", client_id: client.client_id, redirect_uri: REDIRECT_URI,
      code_challenge: @challenge, code_challenge_method: "S256", scope: scopes.join(" "),
      state: "opaque-state", resource: Oauth::Metadata.resource
    }
  end
end
