require Rails.root.join("lib/docket/vault_keyring")

keyring = Docket::VaultKeyring.current
encryption = Rails.application.config.active_record.encryption

# The connector/shared-credential vault uses Docket::VaultKeyring's explicit
# versioned provider. These global credentials keep any future `encrypts`
# declaration independent from SECRET_KEY_BASE too; the last key is active and
# earlier keys remain readable during rotation.
encryption.primary_key = keyring.secrets_in_read_order
encryption.deterministic_key = keyring.active_secret
encryption.key_derivation_salt = Digest::SHA256.hexdigest("docket-vault-key-derivation-v1")
encryption.store_key_references = true

Rails.application.config.x.vault_keyring = keyring
