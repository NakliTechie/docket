module Connectors
  # OAuth2 provider: append rows to a Google Sheet via the Sheets v4 API. The
  # operator registers a Google Cloud OAuth client (client_id config +
  # client_secret credential) and names a default spreadsheet, connects once
  # through the browser, then the agent can append a row. Appending is :confirm
  # — a human reviews the values before they land. Effector-only (no inbound
  # sync; reading a sheet back in would be a separate sync provider).
  class GoogleSheetsProvider < OauthProvider
    API_BASE = "https://sheets.googleapis.com".freeze

    def self.authorize_endpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    def self.token_endpoint     = "https://oauth2.googleapis.com/token"
    def self.oauth_scope        = "https://www.googleapis.com/auth/spreadsheets"
    def self.extra_authorize_params = { "access_type" => "offline", "prompt" => "consent" }

    def self.descriptor
      Descriptor.new(
        key: "google_sheets", name: "Google Sheets", category: "Productivity",
        auth: :none, config_fields: %w[client_id spreadsheet_id],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "append_row", name: "Append row",
          summary: "Append a row of values to a Google Sheet.",
          params: {
            "type" => "object",
            "properties" => {
              "values" => {
                "type" => "array",
                "items" => { "type" => "string" },
                "description" => "Cell values for the new row, left to right"
              },
              "range" => { "type" => "string", "description" => "Sheet/range to append into (default Sheet1)" },
              "spreadsheet_id" => { "type" => "string", "description" => "Override the connector's default spreadsheet (optional)" }
            },
            "required" => %w[values]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "append_row" then append_row(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def append_row(args)
      values = args["values"] || args[:values]
      raise Connectors::Error, "values must be a non-empty array" unless values.is_a?(Array) && values.any?
      range = (args["range"] || args[:range]).to_s.strip.presence || "Sheet1"

      path = "/v4/spreadsheets/#{CGI.escape(spreadsheet_id(args))}/values/#{CGI.escape(range)}:append" \
             "?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS"
      uri = build_uri(API_BASE, path)
      body = { "values" => [ values.map(&:to_s) ] }
      resp = ensure_ok!(post_json(uri, body, headers: auth_headers), "Google Sheets")
      { "ok" => true, "result" => parse_json(resp.body) }
    end

    def spreadsheet_id(args)
      id = (args["spreadsheet_id"] || args[:spreadsheet_id]).to_s.strip
      id = connector.config_value("spreadsheet_id").to_s.strip if id.blank?
      raise Connectors::Error, "spreadsheet_id is required" if id.blank?
      id
    end
  end
end
