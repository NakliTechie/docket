module Connectors
  # OAuth2 provider: the HubSpot CRM via a public-app OAuth grant, rather than
  # the static Private-App token the `hubspot` provider uses. Same v3 CRM
  # endpoints + create_contact / create_deal actions, but the Bearer token is
  # minted + refreshed through the OauthProvider seam. Use this when the
  # operator installs a HubSpot OAuth app; use `hubspot` for a private-app token.
  # Effector-only.
  class HubspotOauthProvider < OauthProvider
    API_BASE = "https://api.hubapi.com".freeze

    def self.authorize_endpoint = "https://app.hubspot.com/oauth/authorize"
    def self.token_endpoint     = "https://api.hubapi.com/oauth/v1/token"
    def self.oauth_scope        = "crm.objects.contacts.write crm.objects.deals.write"

    def self.descriptor
      Descriptor.new(
        key: "hubspot_oauth", name: "HubSpot (OAuth)", category: "CRM & Sales",
        auth: :none, config_fields: %w[client_id],
        credential_fields: %w[client_secret], syncs: false
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
              "email" => { "type" => "string", "description" => "Contact email (the unique key)" },
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

    private

    def create_contact(args)
      email = blank_to_nil(args["email"] || args[:email])
      raise Connectors::Error, "email is required" if email.nil?

      properties = { "email" => email }
      %w[firstname lastname phone company].each do |key|
        value = blank_to_nil(args[key] || args[key.to_sym])
        properties[key] = value unless value.nil?
      end

      uri = build_uri(API_BASE, "/crm/v3/objects/contacts")
      resp = ensure_ok!(post_json(uri, { "properties" => properties }, headers: auth_headers), "HubSpot")
      { "ok" => true, "contact" => parse_json(resp.body) }
    end

    def create_deal(args)
      dealname = blank_to_nil(args["dealname"] || args[:dealname])
      raise Connectors::Error, "dealname is required" if dealname.nil?

      properties = { "dealname" => dealname }
      amount = blank_to_nil(args["amount"] || args[:amount])
      properties["amount"] = amount unless amount.nil?

      uri = build_uri(API_BASE, "/crm/v3/objects/deals")
      resp = ensure_ok!(post_json(uri, { "properties" => properties }, headers: auth_headers), "HubSpot")
      { "ok" => true, "deal" => parse_json(resp.body) }
    end

    def blank_to_nil(value)
      str = value.to_s.strip
      str.empty? ? nil : str
    end
  end
end
