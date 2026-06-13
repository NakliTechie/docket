module Connectors
  # CRM effector for Pipedrive's v1 API. Auth is a Pipedrive API token, but
  # — unlike the Bearer-header CRMs — Pipedrive authenticates via a QUERY
  # PARAM: every request carries ?api_token=<token>. The token is a secret
  # kept in the credential vault; the company subdomain (e.g. "acme" →
  # https://acme.pipedrive.com) is non-secret config.
  #
  # Effector-only (syncs: false): the agent can create a person (contact) and
  # a deal. Both are :confirm — the AI prepares the record and a human signs
  # off before it lands in the CRM.
  class PipedriveProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "pipedrive", name: "Pipedrive (CRM)", category: "CRM & Sales",
        auth: :none, config_fields: %w[company_domain],
        credential_fields: %w[api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_person", name: "Create person",
          summary: "Create a Pipedrive person (contact).",
          params: {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string", "description" => "Full name of the person" },
              "email" => { "type" => "string", "description" => "Email address" },
              "phone" => { "type" => "string", "description" => "Phone number" }
            },
            "required" => %w[name]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "create_deal", name: "Create deal",
          summary: "Create a Pipedrive deal.",
          params: {
            "type" => "object",
            "properties" => {
              "title" => { "type" => "string", "description" => "Title of the deal" },
              "value" => { "type" => "string", "description" => "Monetary value of the deal" },
              "currency" => { "type" => "string", "description" => "ISO currency code, e.g. USD" }
            },
            "required" => %w[title]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_person" then create_person(args)
      when "create_deal"   then create_deal(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    # POST /v1/persons — Pipedrive takes email/phone as arrays of strings.
    def create_person(args)
      name = require_arg(args, "name")
      body = { "name" => name }

      email = blank_to_nil(args["email"] || args[:email])
      body["email"] = [ email ] unless email.nil?
      phone = blank_to_nil(args["phone"] || args[:phone])
      body["phone"] = [ phone ] unless phone.nil?

      uri = build_uri(base, "/v1/persons?api_token=#{require_secret('api_token')}")
      response = ensure_ok!(post_json(uri, body, headers: {}), "Pipedrive")
      { "ok" => true, "person" => parse_json(response.body) }
    end

    # POST /v1/deals
    def create_deal(args)
      title = require_arg(args, "title")
      body = { "title" => title }

      value = blank_to_nil(args["value"] || args[:value])
      body["value"] = value unless value.nil?
      currency = blank_to_nil(args["currency"] || args[:currency])
      body["currency"] = currency unless currency.nil?

      uri = build_uri(base, "/v1/deals?api_token=#{require_secret('api_token')}")
      response = ensure_ok!(post_json(uri, body, headers: {}), "Pipedrive")
      { "ok" => true, "deal" => parse_json(response.body) }
    end

    # https://{company_domain}.pipedrive.com
    def base
      "https://#{require_config('company_domain')}.pipedrive.com"
    end

    def require_arg(args, field)
      value = blank_to_nil(args[field] || args[field.to_sym])
      raise Connectors::Error, "#{field} is required" if value.nil?
      value
    end

    def blank_to_nil(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
