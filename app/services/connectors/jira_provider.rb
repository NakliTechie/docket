module Connectors
  # Effector-only provider: create a Jira Cloud issue or comment on one.
  # Auth is Atlassian Cloud Basic auth — username the account email, password
  # the api_token (vaulted). The base is derived per-tenant from the site:
  # https://{site}.atlassian.net. Uses the v2 REST API (plain-text fields, not
  # ADF). Both writes land in the tracked project backlog, so each defaults to
  # :confirm — the AI drafts, a human confirms before it is filed.
  class JiraProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "jira", name: "Jira (issues)", category: "Support & Ticketing",
        auth: :none, config_fields: %w[site email project_key],
        credential_fields: %w[api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "create_issue", name: "Create issue",
          summary: "Create a Jira issue.",
          params: {
            "type" => "object",
            "properties" => {
              "summary" => { "type" => "string", "description" => "Issue summary / title" },
              "description" => { "type" => "string", "description" => "Optional plain-text description" },
              "issue_type" => { "type" => "string", "description" => "Optional issue type name (default 'Task')" }
            },
            "required" => %w[summary]
          },
          effect: :write, decision_class: :confirm
        ),
        Action.new(
          key: "add_comment", name: "Add comment",
          summary: "Comment on a Jira issue.",
          params: {
            "type" => "object",
            "properties" => {
              "issue_key" => { "type" => "string", "description" => "Key of the issue to comment on (e.g. PROJ-123)" },
              "body" => { "type" => "string", "description" => "Plain-text comment body" }
            },
            "required" => %w[issue_key body]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "create_issue" then create_issue(args)
      when "add_comment"  then add_comment(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def create_issue(args)
      summary = arg(args, "summary")
      raise Connectors::Error, "summary is required" if summary.blank?

      issue_type = arg(args, "issue_type").presence || "Task"
      fields = {
        "project" => { "key" => require_config("project_key") },
        "summary" => summary,
        "issuetype" => { "name" => issue_type }
      }
      description = arg(args, "description")
      fields["description"] = description if description.present?

      uri = build_uri(base, "/rest/api/2/issue")
      resp = post_json(uri, { "fields" => fields }, headers: auth_headers)
      ensure_ok!(resp, "Jira")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    def add_comment(args)
      issue_key = arg(args, "issue_key")
      body = arg(args, "body")
      raise Connectors::Error, "issue_key is required" if issue_key.blank?
      raise Connectors::Error, "body is required" if body.blank?

      uri = build_uri(base, "/rest/api/2/issue/#{issue_key}/comment")
      resp = post_json(uri, { "body" => body }, headers: auth_headers)
      ensure_ok!(resp, "Jira")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    def arg(args, key)
      args[key] || args[key.to_sym]
    end

    def base
      "https://#{require_config('site')}.atlassian.net"
    end

    def auth_headers
      { "Authorization" => basic_auth(require_config("email"), require_secret("api_token")) }
    end
  end
end
