require "test_helper"

# The Google Workspace OAuth2 effectors — Gmail (send), Sheets (append), Drive
# (list/create) — built on Connectors::OauthProvider. The token dance + refresh
# is covered by the Google Calendar reference test; here we set a live access
# token directly and exercise each action's wire call + decision class.
class Connectors::GoogleWorkspaceProvidersTest < ActiveSupport::TestCase
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
    c = Connector.create!(name: provider, provider: provider, config: { "client_id" => "cid.apps" }.merge(config))
    c.credentials_hash = { "client_secret" => "topsecret" }
    c.oauth_tokens = tokens if tokens
    c.save!
    c
  end

  def b64url_decode(str)
    s = str.tr("-_", "+/")
    s += "=" * ((4 - s.length % 4) % 4)
    s.unpack1("m0")
  end

  # --- Gmail ---

  test "gmail is an OAuth, effector-only provider and send_email is confirm" do
    assert conn("gmail").oauth?
    assert_not Connectors::GmailProvider.descriptor.syncs?
    assert_equal :confirm, Connectors::GmailProvider.action("send_email").effective_decision_class
  end

  test "gmail send_email posts a base64url MIME message with a Bearer token" do
    c = conn("gmail")
    with_http(200, %({"id":"msg_1","labelIds":["SENT"]})) do |reqs|
      obs = Connectors::GmailProvider.new(c).invoke("send_email",
        { "to" => "a@b.com", "subject" => "Hi there", "body" => "Hello Ada", "cc" => "c@d.com" })
      assert obs["ok"]
      assert_equal "msg_1", obs["message"]["id"]

      req = reqs.last.last
      assert_equal "/gmail/v1/users/me/messages/send", req.path
      assert_equal "Bearer tok", req["Authorization"]
      raw = JSON.parse(req.body)["raw"]
      assert raw.present?
      mime = b64url_decode(raw)
      assert_includes mime, "To: a@b.com"
      assert_includes mime, "Cc: c@d.com"
      assert_includes mime, "Subject: Hi there"
      assert_includes mime, "Hello Ada"
    end
  end

  test "gmail send_email omits Cc when not supplied and requires to/subject/body" do
    c = conn("gmail")
    with_http(200) do |reqs|
      Connectors::GmailProvider.new(c).invoke("send_email", { "to" => "a@b.com", "subject" => "s", "body" => "b" })
      assert_not_includes b64url_decode(JSON.parse(reqs.last.last.body)["raw"]), "Cc:"
    end
    p = Connectors::GmailProvider.new(c)
    assert_raises(Connectors::Error) { p.invoke("send_email", { "subject" => "s", "body" => "b" }) }
    assert_raises(Connectors::Error) { p.invoke("send_email", { "to" => "a@b.com", "body" => "b" }) }
    assert_raises(Connectors::Error) { p.invoke("send_email", { "to" => "a@b.com", "subject" => "s" }) }
  end

  # --- Sheets ---

  test "sheets append_row is a confirm write" do
    assert_equal :confirm, Connectors::GoogleSheetsProvider.action("append_row").effective_decision_class
  end

  test "sheets append_row posts values wrapped as a single row to the default spreadsheet" do
    c = conn("google_sheets", config: { "spreadsheet_id" => "SS_DEFAULT" })
    with_http(200, %({"updates":{"updatedRows":1}})) do |reqs|
      obs = Connectors::GoogleSheetsProvider.new(c).invoke("append_row", { "values" => [ "Ada", "ada@b.com", 42 ] })
      assert obs["ok"]
      req = reqs.last.last
      assert_equal "/v4/spreadsheets/SS_DEFAULT/values/Sheet1:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS", req.path
      assert_equal "Bearer tok", req["Authorization"]
      assert_equal [ [ "Ada", "ada@b.com", "42" ] ], JSON.parse(req.body)["values"]
    end
  end

  test "sheets append_row honours a per-call spreadsheet_id and range override" do
    c = conn("google_sheets", config: { "spreadsheet_id" => "SS_DEFAULT" })
    with_http(200) do |reqs|
      Connectors::GoogleSheetsProvider.new(c).invoke("append_row",
        { "values" => [ "x" ], "range" => "Leads!A1", "spreadsheet_id" => "OTHER" })
      assert_equal "/v4/spreadsheets/OTHER/values/Leads%21A1:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS",
                   reqs.last.last.path
    end
  end

  test "sheets append_row needs a non-empty array and a spreadsheet id" do
    no_default = conn("google_sheets")
    assert_raises(Connectors::Error) { Connectors::GoogleSheetsProvider.new(no_default).invoke("append_row", { "values" => [] }) }
    with_http(200) do |_r|
      # values present but no spreadsheet configured or supplied
      assert_raises(Connectors::Error) { Connectors::GoogleSheetsProvider.new(no_default).invoke("append_row", { "values" => [ "x" ] }) }
    end
  end

  # --- Drive ---

  test "drive list_files is autonomous read; create_file is a confirm write" do
    assert_equal :autonomous, Connectors::GoogleDriveProvider.action("list_files").effective_decision_class
    assert_equal :confirm, Connectors::GoogleDriveProvider.action("create_file").effective_decision_class
  end

  test "drive list_files GETs with a fields projection and bounded page size" do
    c = conn("google_drive")
    with_http(200, %({"files":[{"id":"f1","name":"invoice.pdf"}]})) do |reqs|
      obs = Connectors::GoogleDriveProvider.new(c).invoke("list_files", { "query" => "name contains 'invoice'", "page_size" => 500 })
      assert obs["ok"]
      assert_equal "f1", obs["files"].first["id"]
      req = reqs.last.last
      assert_kind_of Net::HTTP::Get, req
      assert_includes req.path, "/drive/v3/files?"
      assert_includes req.path, "pageSize=100" # 500 clamped to 100
      assert_includes req.path, CGI.escape("name contains 'invoice'")
      assert_equal "Bearer tok", req["Authorization"]
    end
  end

  test "drive create_file uploads a multipart/related body with metadata + content" do
    c = conn("google_drive")
    with_http(200, %({"id":"file_9","name":"notes.txt"})) do |reqs|
      obs = Connectors::GoogleDriveProvider.new(c).invoke("create_file", { "name" => "notes.txt", "content" => "hello world" })
      assert obs["ok"]
      assert_equal "file_9", obs["file"]["id"]
      req = reqs.last.last
      assert_equal "/upload/drive/v3/files?uploadType=multipart", req.path
      assert_match %r{\Amultipart/related; boundary=}, req["Content-Type"]
      assert_includes req.body, %("name":"notes.txt")
      assert_includes req.body, "hello world"
    end
  end

  test "drive create_file requires a name and content" do
    c = conn("google_drive")
    p = Connectors::GoogleDriveProvider.new(c)
    assert_raises(Connectors::Error) { p.invoke("create_file", { "content" => "x" }) }
    assert_raises(Connectors::Error) { p.invoke("create_file", { "name" => "x" }) }
  end

  test "an unknown action raises across the workspace providers" do
    c = conn("gmail")
    assert_raises(Connectors::Error) { Connectors::GmailProvider.new(c).invoke("nope", {}) }
  end
end
