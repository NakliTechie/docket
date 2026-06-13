module Connectors
  # Effector-only Klaviyo (Marketing) provider. Auth is a static private API
  # key sent as "Authorization: Klaviyo-API-Key <api_key>", paired with a
  # required "revision" header that pins the API version so the JSON:API
  # response envelope stays stable; it defaults to "2024-10-15" and an admin
  # can override it via the optional `revision` config. The single action
  # creates a profile (a subscriber) via the JSON:API endpoint; it writes a
  # citizen contact into a marketing list, so it defaults to :confirm — the AI
  # drafts, a human confirms before the profile lands in Klaviyo.
  class KlaviyoProvider < HttpProvider
    DEFAULT_BASE = "https://a.klaviyo.com".freeze
    DEFAULT_REVISION = "2024-10-15".freeze

    def self.descriptor
      Descriptor.new(
        key: "klaviyo", name: "Klaviyo", category: "Marketing",
        auth: :none, config_fields: %w[base_url revision],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_profile", name: "Create profile",
          summary: "Create a Klaviyo profile (subscriber).",
          params: {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string", "description" => "Email address of the profile" },
              "first_name" => { "type" => "string", "description" => "Optional first name" },
              "last_name" => { "type" => "string", "description" => "Optional last name" },
              "phone_number" => { "type" => "string", "description" => "Optional phone number in E.164 format" }
            },
            "required" => %w[email]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_profile" then create_profile(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_profile(args)
      email = blank_to_nil(args["email"] || args[:email])
      raise Connectors::Error, "email is required" if email.nil?

      attributes = { "email" => email }
      %w[first_name last_name phone_number].each do |key|
        value = blank_to_nil(args[key] || args[key.to_sym])
        attributes[key] = value unless value.nil?
      end

      body = { "data" => { "type" => "profile", "attributes" => attributes } }
      uri = build_uri(base, "/api/profiles")
      response = ensure_ok!(post_json(uri, body, headers: auth_headers), "Klaviyo")
      { "ok" => true, "result" => parse_json(response.body) }
    end

    def auth_headers
      {
        "Authorization" => "Klaviyo-API-Key #{require_secret('api_key')}",
        "revision" => revision
      }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def revision
      connector.config_value("revision").presence || DEFAULT_REVISION
    end

    def blank_to_nil(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
