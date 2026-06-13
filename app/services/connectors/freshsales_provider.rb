module Connectors
  # Effector-only CRM provider for Freshsales (Freshworks CRM). Auth is a static
  # API key sent as Freshworks' custom token header — `Authorization: Token
  # token=<api_key>` — kept in the credential vault. The base is derived
  # per-tenant from the Freshworks bundle subdomain:
  # https://{bundle_domain}.myfreshworks.com/crm/sales. The agent can create a
  # contact or a deal; both write to CRM records that a salesperson works, so
  # each defaults to :confirm — the AI drafts, a human confirms before it lands.
  class FreshsalesProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "freshsales", name: "Freshsales (CRM)", category: "CRM & Sales",
        auth: :none, config_fields: %w[bundle_domain], credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_contact", name: "Create contact",
          summary: "Create a Freshsales contact.",
          params: {
            "type" => "object",
            "properties" => {
              "first_name" => { "type" => "string", "description" => "Contact first name" },
              "last_name" => { "type" => "string", "description" => "Contact last name" },
              "email" => { "type" => "string", "description" => "Contact email address" },
              "mobile_number" => { "type" => "string", "description" => "Contact mobile number" }
            },
            "required" => %w[first_name]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "create_deal", name: "Create deal",
          summary: "Create a Freshsales deal.",
          params: {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string", "description" => "Deal name" },
              "amount" => { "type" => "string", "description" => "Deal amount" }
            },
            "required" => %w[name]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_contact" then create_contact(args)
      when "create_deal"    then create_deal(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_contact(args)
      first_name = blank_to_nil(arg(args, "first_name"))
      raise Connectors::Error, "first_name is required" if first_name.nil?

      contact = { "first_name" => first_name }
      %w[last_name email mobile_number].each do |key|
        value = blank_to_nil(arg(args, key))
        contact[key] = value unless value.nil?
      end

      uri = build_uri(base, "/api/contacts")
      resp = post_json(uri, { "contact" => contact }, headers: auth_headers)
      ensure_ok!(resp, "Freshsales")
      { "ok" => true, "contact" => parse_json(resp.body) }
    end

    def create_deal(args)
      name = blank_to_nil(arg(args, "name"))
      raise Connectors::Error, "name is required" if name.nil?

      deal = { "name" => name }
      amount = blank_to_nil(arg(args, "amount"))
      deal["amount"] = amount unless amount.nil?

      uri = build_uri(base, "/api/deals")
      resp = post_json(uri, { "deal" => deal }, headers: auth_headers)
      ensure_ok!(resp, "Freshsales")
      { "ok" => true, "deal" => parse_json(resp.body) }
    end

    def auth_headers
      { "Authorization" => "Token token=#{require_secret('api_key')}" }
    end

    def base
      "https://#{require_config('bundle_domain')}.myfreshworks.com/crm/sales"
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
