module ApiTestHelper
  def api_token_for(user, name: "test")
    ApiToken.create!(user: user, name: name).raw_token
  end

  def service_token_for(scopes, name: "Test Integration")
    account = ServiceAccount.create!(name: "#{name} #{SecureRandom.hex(3)}", scopes: scopes)
    account.issue_access_token!.raw_token
  end

  def auth_header(token)
    { "Authorization" => "Bearer #{token}" }
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include ApiTestHelper
end
