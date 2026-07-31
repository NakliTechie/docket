require "json"
require "pathname"

module Docket
  class VaultKeyring
    class Error < StandardError; end

    VERSION_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}\z/
    KEY_PATTERN = /\A[0-9a-f]{64}\z/i

    attr_reader :active_version

    def self.current
      @current ||= load
    end

    def self.reset!
      @current = nil
    end

    def self.load
      raw = ENV["DOCKET_VAULT_KEYS"].presence
      path = Pathname(ENV.fetch("DOCKET_VAULT_KEYS_PATH", Rails.root.join("storage/vault_keys.json")))
      raw ||= read_file(path)
      raw ||= development_fallback
      raise Error, "vault keyring is missing; set DOCKET_VAULT_KEYS or DOCKET_VAULT_KEYS_PATH" if raw.blank?

      build(raw, include_legacy: ENV.fetch("DOCKET_VAULT_INCLUDE_LEGACY_KEY", "true") != "false")
    end

    def self.build(raw, include_legacy: false)
      parsed = raw.is_a?(Hash) ? raw.deep_stringify_keys : JSON.parse(raw)
      new(active: parsed.fetch("active"), keys: parsed.fetch("keys"),
          include_legacy: include_legacy)
    rescue JSON::ParserError, KeyError => e
      raise Error, "invalid vault keyring: #{e.message}"
    end

    def initialize(active:, keys:, include_legacy: false)
      @active_version = active.to_s
      @keys = keys.to_h.transform_keys(&:to_s).transform_values(&:to_s)
      validate!
      add_legacy_key! if include_legacy
    end

    def versions = @keys.keys
    def active_secret = @keys.fetch(active_version)
    def secrets_in_read_order = versions.map { |version| @keys.fetch(version) }

    def provider
      @provider ||= VersionedKeyProvider.new(keys: @keys, active: active_version)
    end

    def status
      { active: active_version, readable_versions: versions }
    end

    class VersionedKeyProvider
      attr_reader :active_version

      def initialize(keys:, active:)
        @active_version = active.to_s
        @keys = keys.to_h.transform_values do |hex|
          ActiveRecord::Encryption::Key.new([ hex ].pack("H*"))
        end
      end

      def encryption_key
        @encryption_key ||= @keys.fetch(active_version).tap do |key|
          key.public_tags.encrypted_data_key_id = active_version
        end
      end

      def decryption_keys(message)
        version = message.headers.encrypted_data_key_id
        return @keys.values.reverse if version.blank?

        Array(@keys[version.to_s])
      end
    end

    class << self
      private

      def read_file(path)
        return unless path.file?
        if Rails.env.production? && (path.stat.mode & 0o077).positive?
          raise Error, "vault keyring permissions must be 0600: #{path}"
        end

        path.read
      end

      def development_fallback
        return if Rails.env.production?

        secret = Digest::SHA256.hexdigest("docket-#{Rails.env}-vault-development-key")
        { active: "#{Rails.env}-v1", keys: { "#{Rails.env}-v1" => secret } }
      end
    end

    private

    def validate!
      raise Error, "invalid active vault-key version" unless active_version.match?(VERSION_PATTERN)
      raise Error, "active vault-key version is absent" unless @keys.key?(active_version)
      raise Error, "vault keyring must contain at least one key" if @keys.empty?

      @keys.each do |version, key|
        raise Error, "invalid vault-key version #{version.inspect}" unless version.match?(VERSION_PATTERN)
        raise Error, "vault key #{version.inspect} must be exactly 32 bytes of hex" unless key.match?(KEY_PATTERN)
      end
      if @keys.values.map(&:downcase).uniq.size != @keys.size
        raise Error, "vault key material cannot be reused across versions"
      end
    end

    def add_legacy_key!
      return if Rails.application.secret_key_base.blank?

      legacy = legacy_key
      return if @keys.values.any? { |key| ActiveSupport::SecurityUtils.secure_compare(key.downcase, legacy) }

      @keys = { "legacy-secret-key-base" => legacy }.merge(@keys)
    end

    def legacy_key
      secret = Rails.application.secret_key_base.to_s
      generator = ActiveSupport::KeyGenerator.new(
        secret, hash_digest_class: OpenSSL::Digest::SHA256
      )
      password = generator.generate_key("docket-ar-encryption-primary", 32).unpack1("H*")
      salt = generator.generate_key("docket-ar-encryption-salt", 32).unpack1("H*")
      ActiveSupport::KeyGenerator.new(
        password, hash_digest_class: ActiveRecord::Encryption.config.hash_digest_class
      ).generate_key(salt, ActiveRecord::Encryption.cipher.key_length).unpack1("H*")
    end
  end
end
