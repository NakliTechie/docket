require "test_helper"

# The OAuth2 docs/storage effectors — DocuSign (send envelope), Box (list/upload),
# Dropbox (list/upload) — on the Connectors::OauthProvider seam. Token refresh is
# covered by the Google Calendar reference; here a live access token is set
# directly and each action's wire call + decision class is exercised.
class Connectors::DocsStorageOauthProvidersTest < ActiveSupport::TestCase
  class FakeResponse
    def initialize(code, body) = (@code = code; @body = body)
    attr_reader :code, :body
  end
  class FakeHttp
    attr_reader :last
    def initialize(r) = @r = r
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(req) = (@last = req; @r)
  end
  def with_http(code, body = "{}")
    captured = []
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(FakeResponse.new(code.to_s, body)).tap { |h| captured << h } }
    yield captured
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  def conn(provider, config: {}, tokens: { "access_token" => "tok", "expires_at" => 1.hour.from_now.iso8601 })
    c = Connector.create!(name: provider, provider: provider, config: { "client_id" => "cid" }.merge(config))
    c.credentials_hash = { "client_secret" => "sec" }
    c.oauth_tokens = tokens
    c.save!
    c
  end

  # --- DocuSign ---

  test "docusign send_envelope is confirm and posts a template envelope to the account" do
    assert_equal :confirm, Connectors::DocusignProvider.action("send_envelope").effective_decision_class
    c = conn("docusign", config: { "base_uri" => "https://na3.docusign.net", "account_id" => "acc-1" })
    with_http(201, %({"envelopeId":"env-9","status":"sent"})) do |reqs|
      obs = Connectors::DocusignProvider.new(c).invoke("send_envelope",
        { "template_id" => "tmpl-1", "signer_email" => "a@b.com", "signer_name" => "Ada", "email_subject" => "Please sign" })
      assert_equal "env-9", obs["envelope"]["envelopeId"]
      req = reqs.last.last
      assert_equal "/restapi/v2.1/accounts/acc-1/envelopes", req.path
      assert_equal "Bearer tok", req["Authorization"]
      sent = JSON.parse(req.body)
      assert_equal "tmpl-1", sent["templateId"]
      assert_equal "sent", sent["status"]
      assert_equal "Signer", sent["templateRoles"].first["roleName"] # defaulted
      assert_equal "a@b.com", sent["templateRoles"].first["email"]
      assert_equal "Please sign", sent["emailSubject"]
    end
  end

  test "docusign requires base_uri, account_id and the signer fields" do
    missing_cfg = conn("docusign", config: {})
    assert_raises(Connectors::Error) do
      Connectors::DocusignProvider.new(missing_cfg).invoke("send_envelope",
        { "template_id" => "t", "signer_email" => "a@b.com", "signer_name" => "Ada" })
    end
    full = conn("docusign", config: { "base_uri" => "https://na3.docusign.net", "account_id" => "acc-1" })
    assert_raises(Connectors::Error) do
      Connectors::DocusignProvider.new(full).invoke("send_envelope", { "template_id" => "t", "signer_email" => "a@b.com" })
    end
  end

  # --- Box ---

  test "box list_folder is autonomous read; upload_file is a confirm write" do
    assert_equal :autonomous, Connectors::BoxProvider.action("list_folder").effective_decision_class
    assert_equal :confirm, Connectors::BoxProvider.action("upload_file").effective_decision_class
  end

  test "box list_folder GETs items for the default root folder" do
    c = conn("box")
    with_http(200, %({"entries":[{"id":"7","name":"q3.pdf","type":"file"}]})) do |reqs|
      obs = Connectors::BoxProvider.new(c).invoke("list_folder", {})
      assert_equal "7", obs["entries"].first["id"]
      req = reqs.last.last
      assert_equal "/2.0/folders/0/items", req.path
      assert_kind_of Net::HTTP::Get, req
      assert_equal "Bearer tok", req["Authorization"]
    end
  end

  test "box upload_file posts multipart/form-data with an attributes part" do
    c = conn("box")
    with_http(201, %({"entries":[{"id":"file_5","name":"notes.txt"}]})) do |reqs|
      obs = Connectors::BoxProvider.new(c).invoke("upload_file", { "name" => "notes.txt", "content" => "hello", "folder_id" => "123" })
      assert obs["ok"]
      req = reqs.last.last
      assert_equal "/api/2.0/files/content", req.path
      assert_match %r{\Amultipart/form-data; boundary=}, req["Content-Type"]
      assert_includes req.body, %(name="attributes")
      assert_includes req.body, %("id":"123")
      assert_includes req.body, "hello"
    end
  end

  test "box upload_file requires a name and content" do
    p = Connectors::BoxProvider.new(conn("box"))
    assert_raises(Connectors::Error) { p.invoke("upload_file", { "content" => "x" }) }
    assert_raises(Connectors::Error) { p.invoke("upload_file", { "name" => "x" }) }
  end

  # --- Dropbox ---

  test "dropbox list_folder normalises root and posts the path" do
    c = conn("dropbox")
    with_http(200, %({"entries":[{".tag":"file","name":"a.txt"}]})) do |reqs|
      obs = Connectors::DropboxProvider.new(c).invoke("list_folder", { "path" => "/" })
      assert_equal "a.txt", obs["entries"].first["name"]
      req = reqs.last.last
      assert_equal "/2/files/list_folder", req.path
      assert_equal "", JSON.parse(req.body)["path"] # "/" normalised to ""
      assert_equal "Bearer tok", req["Authorization"]
    end
  end

  test "dropbox upload_file sends octet-stream content with a Dropbox-API-Arg header" do
    c = conn("dropbox")
    with_http(200, %({"id":"id:abc","name":"notes.txt"})) do |reqs|
      obs = Connectors::DropboxProvider.new(c).invoke("upload_file", { "path" => "/notes.txt", "content" => "hello world" })
      assert_equal "notes.txt", obs["file"]["name"]
      req = reqs.last.last
      assert_equal "/2/files/upload", req.path
      assert_equal "application/octet-stream", req["Content-Type"]
      arg = JSON.parse(req["Dropbox-API-Arg"])
      assert_equal "/notes.txt", arg["path"]
      assert_equal "add", arg["mode"]
      assert_equal "hello world", req.body
    end
  end

  test "dropbox authorize URL requests offline access for a refresh token" do
    assert_equal "offline", Connectors::DropboxProvider.extra_authorize_params["token_access_type"]
    c = conn("dropbox", tokens: {})
    url = Connectors::DropboxProvider.authorize_url(c, redirect_uri: "https://docket.test/cb", state: "S")
    q = URI.decode_www_form(URI(url).query).to_h
    assert_equal "offline", q["token_access_type"]
  end

  test "dropbox upload_file requires a path and content" do
    p = Connectors::DropboxProvider.new(conn("dropbox"))
    assert_raises(Connectors::Error) { p.invoke("upload_file", { "content" => "x" }) }
    assert_raises(Connectors::Error) { p.invoke("upload_file", { "path" => "/x" }) }
  end
end
