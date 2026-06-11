require "test_helper"

class ServiceAccountTest < ActiveSupport::TestCase
  test "reducing scopes revokes live access tokens so they can't keep the old scopes (M26)" do
    account = ServiceAccount.create!(name: "CRM", scopes: %w[cases:read cases:write])
    account.issue_access_token!
    assert_equal 1, account.oauth_access_tokens.count

    account.update!(scopes: %w[cases:read])
    assert_equal 0, account.oauth_access_tokens.count, "old tokens must be revoked on scope change"
  end

  test "updating a non-scope attribute leaves live tokens intact" do
    account = ServiceAccount.create!(name: "CRM", scopes: %w[cases:read])
    account.issue_access_token!
    account.update!(description: "now with a description")
    assert_equal 1, account.oauth_access_tokens.count
  end
end
