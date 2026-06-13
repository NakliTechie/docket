module Connectors
  # OAuth2 provider: send a DocuSign envelope for signature from a template. The
  # operator registers a DocuSign Authorization-Code-Grant app (client_id config
  # + client_secret credential) and supplies the account-specific `base_uri`
  # (e.g. https://na3.docusign.net) and `account_id` from DocuSign Admin, then
  # connects once through the browser. Sending for signature is :confirm — a
  # human reviews the recipient + template before it goes out (and an envelope
  # can be voided). Effector-only. Defaults to the production OAuth host; demo
  # accounts use account-d.docusign.com.
  class DocusignProvider < OauthProvider
    def self.authorize_endpoint = "https://account.docusign.com/oauth/auth"
    def self.token_endpoint     = "https://account.docusign.com/oauth/token"
    def self.oauth_scope        = "signature"

    def self.descriptor
      Descriptor.new(
        key: "docusign", name: "DocuSign", category: "E-signature & Documents",
        auth: :none, config_fields: %w[client_id base_uri account_id],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "send_envelope", name: "Send envelope from template",
          summary: "Send a DocuSign envelope for signature from a template.",
          params: {
            "type" => "object",
            "properties" => {
              "template_id" => { "type" => "string", "description" => "DocuSign template id" },
              "signer_email" => { "type" => "string", "description" => "Signer email" },
              "signer_name" => { "type" => "string", "description" => "Signer name" },
              "role_name" => { "type" => "string", "description" => "Template role to fill (default Signer)" },
              "email_subject" => { "type" => "string", "description" => "Envelope email subject (optional)" }
            },
            "required" => %w[template_id signer_email signer_name]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "send_envelope" then send_envelope(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def send_envelope(args)
      role = (args["role_name"] || args[:role_name]).to_s.strip.presence || "Signer"
      body = {
        "templateId" => require_arg(args, "template_id"),
        "status" => "sent",
        "templateRoles" => [ {
          "email" => require_arg(args, "signer_email"),
          "name" => require_arg(args, "signer_name"),
          "roleName" => role
        } ]
      }
      subject = (args["email_subject"] || args[:email_subject]).to_s
      body["emailSubject"] = subject if subject.present?

      uri = build_uri(base_uri, "/restapi/v2.1/accounts/#{CGI.escape(account_id)}/envelopes")
      resp = ensure_ok!(post_json(uri, body, headers: auth_headers), "DocuSign")
      { "ok" => true, "envelope" => parse_json(resp.body) }
    end

    def base_uri
      require_config("base_uri").chomp("/")
    end

    def account_id
      require_config("account_id")
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
