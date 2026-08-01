require "base64"
require "openssl"

module Docket
  class DkimSigner
    class ConfigurationError < StandardError; end

    SIGNED_HEADERS = %w[
      from to subject date message-id mime-version content-type content-transfer-encoding
      in-reply-to references list-unsubscribe list-unsubscribe-post
    ].freeze

    def self.from_environment
      domain = ENV["DOCKET_DKIM_DOMAIN"].presence
      selector = ENV["DOCKET_DKIM_SELECTOR"].presence
      private_key = ENV["DOCKET_DKIM_PRIVATE_KEY"].presence
      path = ENV["DOCKET_DKIM_PRIVATE_KEY_PATH"].presence
      configured = [ domain, selector, private_key, path ].compact
      return if configured.empty?
      if domain.blank? || selector.blank? || (private_key.blank? && path.blank?)
        raise ConfigurationError,
              "DKIM requires DOCKET_DKIM_DOMAIN, DOCKET_DKIM_SELECTOR, and a private key or key path"
      end
      raise ConfigurationError, "set only one DKIM private-key source" if private_key && path

      private_key ||= read_key_file(path)
      new(domain: domain, selector: selector, private_key: private_key)
    end

    def self.read_key_file(path)
      file = Pathname(path)
      raise ConfigurationError, "DKIM private key does not exist: #{file}" unless file.file?
      if Rails.env.production? && (file.stat.mode & 0o077).positive?
        raise ConfigurationError, "DKIM private-key permissions must be 0600: #{file}"
      end
      file.read
    end
    private_class_method :read_key_file

    def initialize(domain:, selector:, private_key:)
      @domain = validated_dns_label(domain, "domain", dots: true)
      @selector = validated_dns_label(selector, "selector", dots: false)
      @private_key = OpenSSL::PKey::RSA.new(private_key)
      if @private_key.n.num_bits < 2048
        raise ConfigurationError, "DKIM RSA key must be at least 2048 bits"
      end
    rescue OpenSSL::PKey::RSAError => e
      raise ConfigurationError, "invalid DKIM private key: #{e.message}"
    end

    def delivering_email(message)
      sign(message)
    end

    def sign(message)
      message.header["DKIM-Signature"] = nil
      encoded = message.encoded
      body = encoded.split("\r\n\r\n", 2).last.to_s
      body_hash = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(relaxed_body(body)))
      header_names = SIGNED_HEADERS.select { |name| message.header[name] }
      value = "v=1; a=rsa-sha256; c=relaxed/relaxed; d=#{@domain}; s=#{@selector}; " \
              "t=#{Time.current.to_i}; h=#{header_names.join(':')}; bh=#{body_hash}; b="
      signing_data = header_names.filter_map do |name|
        relaxed_header(message.header[name]&.encoded)
      end.join
      signing_data << relaxed_header("DKIM-Signature: #{value}\r\n")
      signature = @private_key.sign(OpenSSL::Digest::SHA256.new, signing_data)
      message.header["DKIM-Signature"] = "#{value}#{Base64.strict_encode64(signature)}"
      message
    end

    def relaxed_header(encoded)
      unfolded = encoded.to_s.gsub(/\r?\n[ \t]+/, " ").sub(/\r?\n\z/, "")
      name, value = unfolded.split(":", 2)
      "#{name.to_s.downcase}:#{value.to_s.gsub(/[ \t]+/, ' ').strip}\r\n"
    end

    def relaxed_body(body)
      lines = body.to_s.gsub(/\r?\n/, "\n").split("\n", -1).map do |line|
        line.gsub(/[ \t]+/, " ").rstrip
      end
      lines.pop while lines.last == ""
      "#{lines.join("\r\n")}\r\n"
    end

    private

    def validated_dns_label(value, label, dots:)
      pattern = dots ? /\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/i : /\A[a-z0-9][a-z0-9_-]*\z/i
      normalized = value.to_s.strip.downcase
      raise ConfigurationError, "invalid DKIM #{label}" unless normalized.match?(pattern)

      normalized
    end
  end
end
