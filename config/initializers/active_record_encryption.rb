# Derive ActiveRecord encryption keys from the deployment's own
# secret_key_base so the connector credential vault works with zero extra
# operator setup — the same sovereign-secret model as the rest of Docket
# (the entrypoint persists secret_key_base; we never ship a key).
secret = Rails.application.secret_key_base.to_s
if secret.present?
  gen = ActiveSupport::KeyGenerator.new(secret, hash_digest_class: OpenSSL::Digest::SHA256)
  enc = Rails.application.config.active_record.encryption
  enc.primary_key        = gen.generate_key("docket-ar-encryption-primary", 32).unpack1("H*")
  enc.deterministic_key  = gen.generate_key("docket-ar-encryption-deterministic", 32).unpack1("H*")
  enc.key_derivation_salt = gen.generate_key("docket-ar-encryption-salt", 32).unpack1("H*")
end
