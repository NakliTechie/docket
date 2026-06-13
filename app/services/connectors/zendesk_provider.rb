module Connectors
  # Effector-only provider: open a Zendesk support ticket or append a comment.
  # Auth is API-token Basic auth — username "<email>/token", password the
  # api_token (vaulted). The base is derived per-tenant from the subdomain:
  # https://{subdomain}.zendesk.com. Both writes touch citizen-facing support
  # records, so each defaults to :confirm — the AI drafts, a human confirms
  # before it lands in the helpdesk.
  class ZendeskProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "zendesk", name: "Zendesk (support)", category: "Support & Ticketing",
        auth: :none, config_fields: %w[subdomain email], credential_fields: %w[api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_ticket", name: "Create ticket",
          summary: "Open a Zendesk support ticket.",
          params: {
            "type" => "object",
            "properties" => {
              "subject" => { "type" => "string", "description" => "Ticket subject line" },
              "body" => { "type" => "string", "description" => "First comment / description" },
              "priority" => { "type" => "string", "description" => "Optional: urgent | high | normal | low" }
            },
            "required" => %w[subject body]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "add_comment", name: "Add ticket comment",
          summary: "Add a public or internal comment to a Zendesk ticket.",
          params: {
            "type" => "object",
            "properties" => {
              "ticket_id" => { "type" => "string", "description" => "Id of the ticket to comment on" },
              "body" => { "type" => "string", "description" => "Comment text" },
              "public" => { "type" => "boolean", "description" => "Public reply (true, default) or internal note (false)" }
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
      when "add_comment"   then add_comment(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_ticket(args)
      subject = arg(args, "subject")
      body = arg(args, "body")
      raise Connectors::Error, "subject is required" if subject.blank?
      raise Connectors::Error, "body is required" if body.blank?

      ticket = { "subject" => subject, "comment" => { "body" => body } }
      priority = arg(args, "priority")
      ticket["priority"] = priority if priority.present?

      uri = build_uri(base, "/api/v2/tickets.json")
      resp = post_json(uri, { "ticket" => ticket }, headers: auth_headers)
      ensure_ok!(resp, "Zendesk")
      { "ok" => true, "ticket" => parse_json(resp.body) }
    end

    def add_comment(args)
      ticket_id = arg(args, "ticket_id")
      body = arg(args, "body")
      raise Connectors::Error, "ticket_id is required" if ticket_id.blank?
      raise Connectors::Error, "body is required" if body.blank?

      # Read `public` without arg()'s `||` fallthrough — that turns an explicit
      # false into nil (false || nil → nil). Default to a public reply.
      is_public =
        if args.key?("public") || args.key?(:public)
          ActiveModel::Type::Boolean.new.cast(args.key?("public") ? args["public"] : args[:public])
        else
          true
        end
      comment = { "body" => body, "public" => is_public }

      uri = build_uri(base, "/api/v2/tickets/#{ticket_id}.json")
      resp = put_json(uri, { "ticket" => { "comment" => comment } }, headers: auth_headers)
      ensure_ok!(resp, "Zendesk")
      { "ok" => true, "ticket" => parse_json(resp.body) }
    end

    def arg(args, key)
      args[key] || args[key.to_sym]
    end

    def base
      "https://#{require_config('subdomain')}.zendesk.com"
    end

    def auth_headers
      { "Authorization" => basic_auth("#{require_config('email')}/token", require_secret("api_token")) }
    end
  end
end
