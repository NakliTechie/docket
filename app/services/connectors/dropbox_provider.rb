module Connectors
  # OAuth2 provider: list a Dropbox folder and upload files. The operator
  # registers a Dropbox app (client_id config + client_secret credential) and
  # connects once through the browser. token_access_type=offline on the
  # authorize URL is what yields a refresh token. Listing is :read (autonomous);
  # uploading is :confirm. Dropbox splits hosts: api.dropboxapi.com for RPC,
  # content.dropboxapi.com for content. Effector-only.
  class DropboxProvider < OauthProvider
    API_BASE = "https://api.dropboxapi.com".freeze
    CONTENT_BASE = "https://content.dropboxapi.com".freeze

    def self.authorize_endpoint = "https://www.dropbox.com/oauth2/authorize"
    def self.token_endpoint     = "https://api.dropboxapi.com/oauth2/token"
    def self.oauth_scope        = "files.metadata.read files.content.read files.content.write"
    def self.extra_authorize_params = { "token_access_type" => "offline" }

    def self.descriptor
      Descriptor.new(
        key: "dropbox", name: "Dropbox", category: "Storage & Files",
        auth: :none, config_fields: %w[client_id],
        credential_fields: %w[client_secret], syncs: false
      )
    end

    def self.actions
      [
        Action.new(
          key: "list_folder", name: "List folder",
          summary: "List the entries in a Dropbox folder (default the root).",
          params: {
            "type" => "object",
            "properties" => {
              "path" => { "type" => "string", "description" => "Folder path, e.g. /invoices ('' or '/' for root)" }
            }
          },
          effect: :read, decision_class: :autonomous
        ),
        Action.new(
          key: "upload_file", name: "Upload file",
          summary: "Upload a text file to Dropbox at the given path.",
          params: {
            "type" => "object",
            "properties" => {
              "path" => { "type" => "string", "description" => "Destination path including filename, e.g. /notes.txt" },
              "content" => { "type" => "string", "description" => "Text content of the file" }
            },
            "required" => %w[path content]
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
      # Dropbox wants "" for the root, not "/".
      path = (args["path"] || args[:path]).to_s.strip
      path = "" if path.empty? || path == "/"
      uri = build_uri(API_BASE, "/2/files/list_folder")
      resp = ensure_ok!(post_json(uri, { "path" => path }, headers: auth_headers), "Dropbox")
      body = parse_json(resp.body)
      { "ok" => true, "entries" => (body.is_a?(Hash) ? Array(body["entries"]) : []) }
    end

    def upload_file(args)
      path = require_arg(args, "path")
      content = require_arg(args, "content")
      api_arg = JSON.generate({ "path" => path, "mode" => "add", "autorename" => true })

      uri = build_uri(CONTENT_BASE, "/2/files/upload")
      req = Net::HTTP::Post.new(uri.request_uri,
        base_headers.merge(auth_headers).merge(
          "Content-Type" => "application/octet-stream",
          "Dropbox-API-Arg" => api_arg
        ))
      req.body = content
      resp = ensure_ok!(perform(req, uri), "Dropbox")
      { "ok" => true, "file" => parse_json(resp.body) }
    end

    def require_arg(args, field)
      value = (args[field] || args[field.to_sym]).to_s
      raise Connectors::Error, "#{field} is required" if value.strip.empty?
      value
    end
  end
end
