module Connectors
  # OAuth2 provider: list a Box folder and upload files. The operator registers a
  # Box OAuth2 app (client_id config + client_secret credential) and connects
  # once through the browser. Listing is :read (autonomous); uploading is
  # :confirm. Box splits hosts: api.box.com for metadata, upload.box.com for
  # content. Effector-only.
  class BoxProvider < OauthProvider
    API_BASE = "https://api.box.com".freeze
    UPLOAD_BASE = "https://upload.box.com".freeze

    def self.authorize_endpoint = "https://account.box.com/api/oauth2/authorize"
    def self.token_endpoint     = "https://api.box.com/oauth2/token"

    def self.descriptor
      Descriptor.new(
        key: "box", name: "Box", category: "Storage & Files",
        auth: :none, config_fields: %w[client_id],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "list_folder", name: "List folder",
          summary: "List the items in a Box folder (default the root folder).",
          params: {
            "type" => "object",
            "properties" => {
              "folder_id" => { "type" => "string", "description" => "Box folder id (default 0 = All Files root)" }
            }
          },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "upload_file", name: "Upload file",
          summary: "Upload a text file to a Box folder.",
          params: {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string", "description" => "File name" },
              "content" => { "type" => "string", "description" => "Text content of the file" },
              "folder_id" => { "type" => "string", "description" => "Destination folder id (default 0)" }
            },
            "required" => %w[name content]
          },
          effect: :write, decision_class: :confirm
        )
      ]
    end

    def invoke(action_key, args, _context = {})
      case action_key.to_s
      when "list_folder" then list_folder(args)
      when "upload_file" then upload_file(args)
      else raise Connectors::Error, "unknown action: #{action_key}"
      end
    end

    private

    def list_folder(args)
      folder_id = (args["folder_id"] || args[:folder_id]).to_s.strip.presence || "0"
      uri = build_uri(API_BASE, "/2.0/folders/#{CGI.escape(folder_id)}/items")
      resp = ensure_ok!(get(uri, headers: auth_headers), "Box")
      body = parse_json(resp.body)
      { "ok" => true, "entries" => (body.is_a?(Hash) ? Array(body["entries"]) : []) }
    end

    def upload_file(args)
      name = require_arg(args, "name")
      content = require_arg(args, "content")
      folder_id = (args["folder_id"] || args[:folder_id]).to_s.strip.presence || "0"
      attributes = { "name" => name, "parent" => { "id" => folder_id } }

      uri = build_uri(UPLOAD_BASE, "/api/2.0/files/content")
      resp = ensure_ok!(post_multipart_form(uri, attributes, name, content), "Box")
      { "ok" => true, "file" => parse_json(resp.body) }
    end

    # Box's upload is multipart/form-data: a JSON "attributes" field + the
    # "file" part carrying the bytes.
    def post_multipart_form(uri, attributes, filename, content)
      boundary = "docket_box_#{SecureRandom.hex(12)}"
      body = +""
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"attributes\"\r\n\r\n"
      body << JSON.generate(attributes) << "\r\n"
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
      body << "Content-Type: application/octet-stream\r\n\r\n"
      body << content << "\r\n--#{boundary}--"

      req = Net::HTTP::Post.new(uri.request_uri,
        base_headers.merge(auth_headers).merge("Content-Type" => "multipart/form-data; boundary=#{boundary}"))
      req.body = body
      perform(req, uri)
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s
      raise Connectors::Error, "#{field} is required" if value.strip.empty?
      value
    end
  end
end
