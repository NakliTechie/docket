module Connectors
  # Effector-only ActiveCampaign (Marketing v3) provider: create a contact.
  # Auth is the static `Api-Token` header carrying the vaulted account API
  # token. The base is the per-account API URL the admin supplies
  # (e.g. https://youraccount.api-us1.com), derived from config — there is no
  # shared default. Creating a contact writes a citizen record into a marketing
  # account, so it defaults to :confirm — the AI drafts, a human confirms
  # before the contact lands.
  class ActivecampaignProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "activecampaign", name: "ActiveCampaign", category: "Marketing",
        auth: :none, config_fields: %w[api_url], credential_fields: %w[api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_contact", name: "Create contact",
          summary: "Create an ActiveCampaign contact.",
          params: {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string", "description" => "Email address of the contact" },
              "firstName" => { "type" => "string", "description" => "Optional first name" },
              "lastName" => { "type" => "string", "description" => "Optional last name" },
              "phone" => { "type" => "string", "description" => "Optional phone number" }
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
      email = blank_to_nil(arg(args, "email"))
      raise Connectors::Error, "email is required" if email.nil?

      contact = { "email" => email }
      %w[firstName lastName phone].each do |key|
        value = blank_to_nil(arg(args, key))
        contact[key] = value unless value.nil?
      end

      uri = build_uri(base, "/api/3/contacts")
      resp = post_json(uri, { "contact" => contact }, headers: auth_headers)
      ensure_ok!(resp, "ActiveCampaign")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    def auth_headers
      { "Api-Token" => require_secret("api_token") }
    end

    def base
      require_config("api_url")
    end

    def arg(args, key)
      args[key] || args[key.to_sym]
    end

    def blank_to_nil(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
