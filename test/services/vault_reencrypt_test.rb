require "test_helper"

class VaultReencryptTest < ActiveSupport::TestCase
  test "rewrites every encrypted attribute without exposing or changing plaintext" do
    connector = Connector.create!(name: "Vault rotation", provider: "http_json", status: :draft,
                                  target: "contacts", field_mapping: { "external_id" => "id" })
    connector.credentials_hash = { "api_key" => "rotation-secret" }
    connector.oauth_tokens = { "access_token" => "oauth-secret" }
    connector.save!
    credential = SharedCredential.new(name: "rotation", label: "Rotation")
    credential.secrets_hash = { "token" => "shared-secret" }
    credential.save!
    Setting.set("llm_api_key", "llm-secret")
    endpoint = WebhookEndpoint.create!(name: "rotation hook", url: "https://example.com/hook",
                                       events: [ "case.created" ])
    before = [ connector.ciphertext_for(:credentials), connector.ciphertext_for(:oauth_credentials),
               connector.ciphertext_for(:webhook_secret), credential.ciphertext_for(:secrets),
               Setting.find_by!(key: "llm_api_key").ciphertext_for(:value), endpoint.ciphertext_for(:secret) ]

    result = Vault::Reencrypt.call

    assert_operator result.records, :>=, 2
    assert_operator result.attributes, :>=, 3
    assert_empty result.errors
    assert_equal "rotation-secret", connector.reload.credentials_hash["api_key"]
    assert_equal "oauth-secret", connector.oauth_tokens["access_token"]
    assert_equal "shared-secret", credential.reload.secrets_hash["token"]
    assert_equal "llm-secret", Setting.get("llm_api_key")
    assert endpoint.reload.secret.start_with?("whsec_")
    after = [ connector.ciphertext_for(:credentials), connector.ciphertext_for(:oauth_credentials),
              connector.ciphertext_for(:webhook_secret), credential.ciphertext_for(:secrets),
              Setting.find_by!(key: "llm_api_key").ciphertext_for(:value), endpoint.ciphertext_for(:secret) ]
    refute_equal before, after
  end
end
