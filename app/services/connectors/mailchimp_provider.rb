module Connectors
  # Effector-only Mailchimp (Marketing v3) provider: subscribe a contact to an
  # audience (list). Auth is Basic auth where the username is arbitrary
  # ("docket") and the password is the vaulted api_key, per Mailchimp's
  # convention. The base is derived per-tenant from the datacenter
  # server_prefix (e.g. "us21"): https://{server_prefix}.api.mailchimp.com.
  # Adding a member writes a citizen contact into a marketing audience, so it
  # defaults to :confirm — the AI drafts, a human confirms before the contact
  # is subscribed.
  class MailchimpProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "mailchimp", name: "Mailchimp (email marketing)", category: "Marketing",
        auth: :none, config_fields: %w[server_prefix list_id],
        credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "add_member", name: "Add list member",
          summary: "Subscribe a contact to a Mailchimp audience (list).",
          params: {
            "type" => "object",
            "properties" => {
              "email" => { "type" => "string", "description" => "Email address of the contact to subscribe" },
              "first_name" => { "type" => "string", "description" => "Optional first name (FNAME merge field)" },
              "last_name" => { "type" => "string", "description" => "Optional last name (LNAME merge field)" }
            },
            "required" => %w[email]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "add_member" then add_member(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def add_member(args)
      email = arg(args, "email").to_s.strip
      raise Connectors::Error, "email is required" if email.blank?

      first_name = arg(args, "first_name").to_s.strip
      last_name = arg(args, "last_name").to_s.strip
      merge_fields = {}
      merge_fields["FNAME"] = first_name if first_name.present?
      merge_fields["LNAME"] = last_name if last_name.present?

      member = {
        "email_address" => email,
        "status" => "subscribed"
      }
      member["merge_fields"] = merge_fields if merge_fields.present?

      uri = build_uri(base, "/3.0/lists/#{require_config('list_id')}/members")
      resp = post_json(uri, member, headers: auth_headers)
      ensure_ok!(resp, "Mailchimp")
      { "ok" => true, "email" => email, "member" => parse_json(resp.body) }
    end

    def arg(args, key)
      args[key] || args[key.to_sym]
    end

    def base
      "https://#{require_config('server_prefix')}.api.mailchimp.com"
    end

    def auth_headers
      { "Authorization" => basic_auth("docket", require_secret("api_key")) }
    end
  end
end
