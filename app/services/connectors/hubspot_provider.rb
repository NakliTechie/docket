module Connectors
  # CRM provider for HubSpot's v3 CRM API. Auth is a HubSpot Private App
  # token — a static Bearer credential, no OAuth refresh — kept in the
  # credential vault. The agent can create contacts and deals (both :confirm:
  # a human reviews the record before it lands in the CRM) and the provider
  # syncs contacts inbound so each maps cleanly onto a Contact record.
  class HubspotProvider < HttpProvider
    DEFAULT_BASE = "https://api.hubapi.com".freeze

    def self.descriptor
      Descriptor.new(
        key: "hubspot", name: "HubSpot (CRM)", category: "CRM & Sales",
        auth: :none, config_fields: %w[base_url], credential_fields: %w[access_token], syncs: true
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_contact", name: "Create contact",
          summary: "Create a HubSpot contact.",
          params: {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string", "description" => "Contact email (used as the unique key)" },
              "firstname" => { "type" => "string", "description" => "First name" },
              "lastname" => { "type" => "string", "description" => "Last name" },
              "phone" => { "type" => "string", "description" => "Phone number" },
              "company" => { "type" => "string", "description" => "Company name" }
            },
            "required" => %w[email]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "create_deal", name: "Create deal",
          summary: "Create a HubSpot deal.",
          params: {
            "type" => "object",
            "properties" => {
              "dealname" => { "type" => "string", "description" => "Deal name" },
              "amount" => { "type" => "string", "description" => "Deal amount" }
            },
            "required" => %w[dealname]
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

    # Pull contacts inbound so each maps onto a Contact record. HubSpot wraps
    # records as { id:, properties: {...} } — we return the flat properties.
    def fetch
      uri = build_uri(base, "/crm/v3/objects/contacts?properties=email,firstname,lastname,phone")
      response = ensure_ok!(get(uri, headers: auth_headers), "HubSpot")
      body = parse_json(response.body)
      results = body.is_a?(Hash) ? body["results"] : nil
      Array(results).filter_map { |r| r.is_a?(Hash) ? r["properties"] : nil }
    end

    private

    def create_contact(args)
      email = blank_to_nil(args["email"] || args[:email])
      raise Connectors::Error, "email is required" if email.nil?

      properties = { "email" => email }
      %w[firstname lastname phone company].each do |key|
        value = blank_to_nil(args[key] || args[key.to_sym])
        properties[key] = value unless value.nil?
      end

      uri = build_uri(base, "/crm/v3/objects/contacts")
      response = ensure_ok!(post_json(uri, { "properties" => properties }, headers: auth_headers), "HubSpot")
      { "ok" => true, "contact" => parse_json(response.body) }
    end

    def create_deal(args)
      dealname = blank_to_nil(args["dealname"] || args[:dealname])
      raise Connectors::Error, "dealname is required" if dealname.nil?

      properties = { "dealname" => dealname }
      amount = blank_to_nil(args["amount"] || args[:amount])
      properties["amount"] = amount unless amount.nil?

      uri = build_uri(base, "/crm/v3/objects/deals")
      response = ensure_ok!(post_json(uri, { "properties" => properties }, headers: auth_headers), "HubSpot")
      { "ok" => true, "deal" => parse_json(response.body) }
    end

    def auth_headers
      { "Authorization" => bearer(require_secret("access_token")) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def blank_to_nil(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
