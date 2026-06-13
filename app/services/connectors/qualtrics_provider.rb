module Connectors
  # Qualtrics (v3 API). Static API-token credential sent in the `X-API-TOKEN`
  # header (not Bearer). The base host is data-centre specific
  # (https://{dc}.qualtrics.com), so base_url is required config. Read-only
  # effector: list surveys, read a survey definition. Effector-only.
  class QualtricsProvider < HttpProvider
    def self.descriptor
      Descriptor.new(
        key: "qualtrics", name: "Qualtrics", category: "Forms & Surveys",
        auth: :none, config_fields: %w[base_url],
        credential_fields: %w[api_token], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "list_surveys", name: "List surveys",
          summary: "List the account's Qualtrics surveys.",
          params: { "type" => "object", "properties" => {} },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "get_survey", name: "Get survey",
          summary: "Fetch a Qualtrics survey definition by id.",
          params: {
            "type" => "object",
            "properties" => {
              "survey_id" => { "type" => "string", "description" => "Qualtrics survey id (e.g. SV_xxxxx)" }
            },
            "required" => %w[survey_id]
          },
          effect: :read, decision_class: :autonomous
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "list_surveys" then list_surveys
      when "get_survey" then get_survey(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def list_surveys
      uri = build_uri(base, "/API/v3/surveys")
      resp = ensure_ok!(get(uri, headers: auth_headers), "Qualtrics")
      body = parse_json(resp.body)
      { "ok" => true, "surveys" => (body.is_a?(Hash) ? Array(body.dig("result", "elements")) : []) }
    end

    def get_survey(args)
      survey_id = require_arg(args, "survey_id")
      uri = build_uri(base, "/API/v3/surveys/#{CGI.escape(survey_id)}")
      resp = ensure_ok!(get(uri, headers: auth_headers), "Qualtrics")
      body = parse_json(resp.body)
      { "ok" => true, "survey" => (body.is_a?(Hash) ? body["result"] : body) }
    end

    def auth_headers
      { "X-API-TOKEN" => require_secret("api_token") }
    end

    def base
      require_config("base_url").chomp("/")
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s.strip
      raise Connectors::Error, "#{field} is required" if value.blank?
      value
    end
  end
end
