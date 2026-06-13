module Connectors
  # SurveyMonkey (v3 API). Static Bearer access-token credential. Read-only
  # effector: list surveys and pull bulk responses (e.g. to triage feedback or
  # enrich a contact). Both autonomous reads. Effector-only.
  class SurveymonkeyProvider < HttpProvider
    DEFAULT_BASE = "https://api.surveymonkey.com/v3".freeze

    def self.descriptor
      Descriptor.new(
        key: "surveymonkey", name: "SurveyMonkey", category: "Forms & Surveys",
        auth: :none, config_fields: %w[base_url],
        credential_fields: %w[access_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "list_surveys", name: "List surveys",
          summary: "List the account's SurveyMonkey surveys.",
          params: {
            "type" => "object",
            "properties" => {
              "per_page" => { "type" => "integer", "description" => "Surveys per page (default 25, max 100)" }
            }
          },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "get_responses", name: "Get survey responses",
          summary: "Fetch bulk responses for a SurveyMonkey survey.",
          params: {
            "type" => "object",
            "properties" => {
              "survey_id" => { "type" => "string", "description" => "Survey id" },
              "per_page" => { "type" => "integer", "description" => "Responses per page (default 25, max 100)" }
            },
            "required" => %w[survey_id]
          },
          effect: :read, decision_class: :autonomous
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "list_surveys" then list_surveys(args)
      when "get_responses" then get_responses(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def list_surveys(args)
      uri = build_uri(base, "/surveys?per_page=#{per_page(args)}")
      resp = ensure_ok!(get(uri, headers: auth_headers), "SurveyMonkey")
      body = parse_json(resp.body)
      { "ok" => true, "surveys" => (body.is_a?(Hash) ? Array(body["data"]) : []) }
    end

    def get_responses(args)
      survey_id = require_arg(args, "survey_id")
      uri = build_uri(base, "/surveys/#{CGI.escape(survey_id)}/responses/bulk?per_page=#{per_page(args)}")
      resp = ensure_ok!(get(uri, headers: auth_headers), "SurveyMonkey")
      body = parse_json(resp.body)
      { "ok" => true, "responses" => (body.is_a?(Hash) ? Array(body["data"]) : []) }
    end

    def auth_headers
      { "Authorization" => bearer(require_secret("access_token")) }
    end

    def base
      connector.config_value("base_url").presence || DEFAULT_BASE
    end

    def per_page(args)
      n = (args["per_page"] || args[:per_page]).to_i
      return 25 if n <= 0
      [ n, 100 ].min
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
