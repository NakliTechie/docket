module Connectors
  # OAuth2 provider: list and create files in Google Drive via the Drive v3 API.
  # Scoped to drive.file — the connector only sees files it created, which keeps
  # the grant least-privilege. Listing is :read (autonomous); creating a file is
  # :confirm (a human reviews before it lands). Effector-only.
  class GoogleDriveProvider < OauthProvider
    API_BASE = "https://www.googleapis.com".freeze

    def self.authorize_endpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    def self.token_endpoint     = "https://oauth2.googleapis.com/token"
    def self.oauth_scope        = "https://www.googleapis.com/auth/drive.file"
    def self.extra_authorize_params = { "access_type" => "offline", "prompt" => "consent" }

    def self.descriptor
      Descriptor.new(
        key: "google_drive", name: "Google Drive", category: "Storage & Files",
        auth: :none, config_fields: %w[client_id],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "list_files", name: "List files",
          summary: "List files the connector can access in Google Drive.",
          params: {
            "type" => "object",
            "properties" => {
              "query" => { "type" => "string", "description" => "Drive query, e.g. name contains 'invoice' (optional)" },
              "page_size" => { "type" => "integer", "description" => "Max files to return (default 25, max 100)" }
            }
          },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "create_file", name: "Create file",
          summary: "Create a text file in Google Drive with the given name and contents.",
          params: {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string", "description" => "File name" },
              "content" => { "type" => "string", "description" => "Text content of the file" },
              "mime_type" => { "type" => "string", "description" => "MIME type (default text/plain)" }
            },
            "required" => %w[name content]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "list_files"  then list_files(args)
      when "create_file" then create_file(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def list_files(args)
      params = { "fields" => "files(id,name,mimeType,modifiedTime)", "pageSize" => page_size(args) }
      query = (args["query"] || args[:query]).to_s.strip
      params["q"] = query if query.present?
      uri = build_uri(API_BASE, "/drive/v3/files?#{URI.encode_www_form(params)}")
      resp = ensure_ok!(get(uri, headers: auth_headers), "Google Drive")
      body = parse_json(resp.body)
      { "ok" => true, "files" => (body.is_a?(Hash) ? Array(body["files"]) : []) }
    end

    def create_file(args)
      name = require_arg(args, "name")
      content = require_arg(args, "content")
      mime = (args["mime_type"] || args[:mime_type]).to_s.strip.presence || "text/plain"

      uri = build_uri(API_BASE, "/upload/drive/v3/files?uploadType=multipart")
      resp = ensure_ok!(post_multipart_related(uri, { "name" => name }, content, mime), "Google Drive")
      { "ok" => true, "file" => parse_json(resp.body) }
    end

    # Drive's multipart upload: a JSON metadata part followed by the media part.
    def post_multipart_related(uri, metadata, content, mime)
      boundary = "docket_drive_#{SecureRandom.hex(12)}"
      body = +""
      body << "--#{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
      body << JSON.generate(metadata) << "\r\n"
      body << "--#{boundary}\r\nContent-Type: #{mime}\r\n\r\n"
      body << content << "\r\n--#{boundary}--"

      req = Net::HTTP::Post.new(uri.request_uri,
        base_headers.merge(auth_headers).merge("Content-Type" => "multipart/related; boundary=#{boundary}"))
      req.body = body
      perform(req, uri)
    end

    def page_size(args)
      size = (args["page_size"] || args[:page_size]).to_i
      return 25 if size <= 0
      [ size, 100 ].min
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s
      raise Connectors::Error, "#{field} is required" if value.strip.empty?
      value
    end
  end
end
