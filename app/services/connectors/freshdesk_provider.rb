module Connectors
  # Effector-only Freshdesk support provider: open a ticket or post a reply.
  # Auth is API-key Basic auth — the api_key (vaulted) is the username and the
  # literal "X" is the password, per Freshdesk's v2 convention. The base is
  # derived per-tenant from the account subdomain:
  # https://{domain}.freshdesk.com. Both writes touch citizen-facing support
  # records, so each defaults to :confirm — the AI drafts, a human confirms
  # before it lands in the helpdesk.
  class FreshdeskProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "freshdesk", name: "Freshdesk (support)", category: "Support & Ticketing",
        auth: :none, config_fields: %w[domain], credential_fields: %w[api_key], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_ticket", name: "Create ticket",
          summary: "Open a Freshdesk support ticket.",
          params: {
            "type" => "object",
            "properties" => {
              "subject" => { "type" => "string", "description" => "Ticket subject line" },
              "description" => { "type" => "string", "description" => "Ticket description / first message (HTML or text)" },
              "email" => { "type" => "string", "description" => "Email address of the requester" },
              "priority" => { "type" => "integer", "description" => "Optional priority: 1 (low) .. 4 (urgent). Defaults to 1." }
            },
            "required" => %w[subject description email]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "reply_ticket", name: "Reply to ticket",
          summary: "Post a reply to a Freshdesk ticket.",
          params: {
            "type" => "object",
            "properties" => {
              "ticket_id" => { "type" => "string", "description" => "Id of the ticket to reply to" },
              "body" => { "type" => "string", "description" => "Reply body (HTML or text)" }
            },
            "required" => %w[ticket_id body]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_ticket" then create_ticket(args)
      when "reply_ticket"  then reply_ticket(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_ticket(args)
      subject = arg(args, "subject")
      description = arg(args, "description")
      email = arg(args, "email")
      raise Connectors::Error, "subject is required" if subject.blank?
      raise Connectors::Error, "description is required" if description.blank?
      raise Connectors::Error, "email is required" if email.blank?

      priority = arg(args, "priority")
      ticket = {
        "subject" => subject,
        "description" => description,
        "email" => email,
        "priority" => priority.present? ? priority.to_i : 1,
        "status" => 2
      }

      uri = build_uri(base, "/api/v2/tickets")
      resp = post_json(uri, ticket, headers: auth_headers)
      ensure_ok!(resp, "Freshdesk")
      { "ok" => true, "ticket" => parse_json(resp.body) }
    end

    def reply_ticket(args)
      ticket_id = arg(args, "ticket_id")
      body = arg(args, "body")
      raise Connectors::Error, "ticket_id is required" if ticket_id.blank?
      raise Connectors::Error, "body is required" if body.blank?

      uri = build_uri(base, "/api/v2/tickets/#{ticket_id}/reply")
      resp = post_json(uri, { "body" => body }, headers: auth_headers)
      ensure_ok!(resp, "Freshdesk")
      { "ok" => true, "reply" => parse_json(resp.body) }
    end

    def arg(args, key)
      args[key] || args[key.to_sym]
    end

    def base
      "https://#{require_config('domain')}.freshdesk.com"
    end

    def auth_headers
      { "Authorization" => basic_auth(require_secret("api_key"), "X") }
    end
  end
end
