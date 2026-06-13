module Connectors
  # Effector-only Intercom support provider. Auth is a static Bearer
  # access_token (an Intercom app access token) kept in the credential vault.
  # Every request also carries an "Intercom-Version" header — pinned to a known
  # API version so the response envelope stays stable; it defaults to "2.11"
  # and an admin can override it via the optional `intercom_version` config.
  # The single action creates a contact (an Intercom "user"); it touches a
  # citizen-facing support record, so it defaults to :confirm — the AI drafts,
  # a human confirms before it lands in Intercom.
  class IntercomProvider < HttpProvider
    DEFAULT_BASE = "https://api.intercom.io".freeze
    DEFAULT_VERSION = "2.11".freeze

    def self.descriptor
      Descriptor.new(
        key: "intercom", name: "Intercom (support)", category: "Support & Ticketing",
        auth: :none, config_fields: %w[base_url], credential_fields: %w[access_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_contact", name: "Create contact",
          summary: "Create an Intercom contact (user).",
          params: {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string", "description" => "Contact email address" },
              "name" => { "type" => "string", "description" => "Full name" },
              "phone" => { "type" => "string", "description" => "Phone number" }
            },
            "required" => %w[email]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_contact" then create_contact(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_contact(args)
      email = blank_to_nil(args["email"] || args[:email])
      raise Connectors::Error, "email is required" if email.nil?

      body = { "role" => "user", "email" => email }
      %w[name phone].each do |key|
        value = blank_to_nil(args[key] || args[key.to_sym])
        body[key] = value unless value.nil?
      end

      uri = build_uri(base, "/contacts")
      response = ensure_ok!(post_json(uri, body, headers: auth_headers), "Intercom")
      { "ok" => true, "contact" => parse_json(response.body) }
    end

    def auth_headers
      {
        "Authorization" => bearer(require_secret("access_token")),
        "Intercom-Version" => intercom_version
      }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def intercom_version
      connector.config_value("intercom_version").presence || DEFAULT_VERSION
    end

    def blank_to_nil(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
