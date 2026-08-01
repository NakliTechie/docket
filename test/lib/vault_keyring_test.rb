require "test_helper"

class VaultKeyringTest < ActiveSupport::TestCase
  OLD_KEY = "11" * 32
  NEW_KEY = "22" * 32

  test "writes the active version tag and reads ciphertext from a previous version" do
    old_ring = Docket::VaultKeyring.build(
      { active: "v1", keys: { "v1" => OLD_KEY } }, include_legacy: false
    )
    new_ring = Docket::VaultKeyring.build(
      { active: "v2", keys: { "v1" => OLD_KEY, "v2" => NEW_KEY } }, include_legacy: false
    )
    encryptor = ActiveRecord::Encryption::Encryptor.new

    old_ciphertext = encryptor.encrypt("historic secret", key_provider: old_ring.provider)
    assert_equal "historic secret",
                 encryptor.decrypt(old_ciphertext, key_provider: new_ring.provider)
    old_message = ActiveRecord::Encryption.message_serializer.load(old_ciphertext)
    assert_equal "v1", old_message.headers.encrypted_data_key_id

    new_ciphertext = encryptor.encrypt("new secret", key_provider: new_ring.provider)
    new_message = ActiveRecord::Encryption.message_serializer.load(new_ciphertext)
    assert_equal "v2", new_message.headers.encrypted_data_key_id
  end

  test "rejects malformed, missing, and reused key material" do
    assert_raises(Docket::VaultKeyring::Error) do
      Docket::VaultKeyring.build({ active: "v2", keys: { "v1" => OLD_KEY } })
    end
    assert_raises(Docket::VaultKeyring::Error) do
      Docket::VaultKeyring.build({ active: "v1", keys: { "v1" => "short" } })
    end
    assert_raises(Docket::VaultKeyring::Error) do
      Docket::VaultKeyring.build(
        { active: "v2", keys: { "v1" => OLD_KEY, "v2" => OLD_KEY } }
      )
    end
  end
end
