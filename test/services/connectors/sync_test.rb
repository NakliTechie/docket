require "test_helper"

class Connectors::SyncTest < ActiveSupport::TestCase
  def connector(mapping: { "external_id" => "id", "email" => "email", "name" => "name", "phone" => "phone" })
    Connector.create!(name: "Pull", provider: "http_json", target: "contacts",
                      config: { "endpoint_url" => "https://api.example.com/c" }, field_mapping: mapping)
  end

  def stub_fetch(conn, records)
    fake = Object.new
    fake.define_singleton_method(:fetch) { records }
    conn.define_singleton_method(:provider_instance) { fake }
  end

  test "creates contacts from fetched records via the field mapping" do
    conn = connector
    stub_fetch(conn, [
      { "id" => "CIF-1", "email" => "alpha@example.com", "name" => "Alpha", "phone" => "+919900000001" },
      { "id" => "CIF-2", "email" => "beta@example.com", "name" => "Beta", "phone" => "" }
    ])
    assert_difference "Contact.count", 2 do
      Connectors::Sync.run(conn)
    end
    alpha = Contact.find_by(external_id: "CIF-1")
    assert_equal "alpha@example.com", alpha.email
    assert_equal "Alpha", alpha.name

    run = conn.connector_runs.last
    assert run.status_success?
    assert_equal 2, run.records_in
    assert_equal 2, run.records_created
    assert_equal Time.current.to_date, conn.reload.last_synced_at.to_date
  end

  test "upserts an existing contact by external_id instead of duplicating" do
    Contact.create!(name: "Old", external_id: "CIF-9", email: "old@example.com")
    conn = connector
    stub_fetch(conn, [ { "id" => "CIF-9", "email" => "new@example.com", "name" => "New" } ])
    assert_no_difference "Contact.count" do
      Connectors::Sync.run(conn)
    end
    assert_equal "new@example.com", Contact.find_by(external_id: "CIF-9").email
    assert_equal 1, conn.connector_runs.last.records_updated
  end

  test "skips records with no mapped identity" do
    conn = connector
    stub_fetch(conn, [ { "id" => "", "email" => "", "name" => "Nameless" } ])
    assert_no_difference "Contact.count" do
      Connectors::Sync.run(conn)
    end
    assert conn.connector_runs.last.status_success?
  end

  test "a provider failure marks the run failed and the connector errored" do
    conn = connector
    fake = Object.new
    fake.define_singleton_method(:fetch) { raise Connectors::Error, "boom" }
    conn.define_singleton_method(:provider_instance) { fake }

    Connectors::Sync.run(conn)
    run = conn.connector_runs.last
    assert run.status_failed?
    assert_includes run.error, "boom"
    assert conn.reload.status_error?
  end

  # --- HttpJsonProvider (network stubbed) ---

  class FakeResponse
    def initialize(code, body)
      @code = code
      @body = body
    end
    attr_reader :code, :body
  end

  class FakeHttp
    def initialize(response) = @response = response
    def use_ssl=(_) ; end
    def open_timeout=(_) ; end
    def read_timeout=(_) ; end
    def request(_req) = @response
  end

  def with_http(response)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) { |*_a| FakeHttp.new(response) }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original)
  end

  test "http_json provider fetches and digs into a records path" do
    conn = Connector.create!(name: "X", provider: "http_json", target: "contacts",
      config: { "endpoint_url" => "https://api.example.com/c", "records_path" => "data.items" },
      field_mapping: { "external_id" => "id" })
    with_http(FakeResponse.new("200", '{"data":{"items":[{"id":"A"},{"id":"B"}]}}')) do
      records = conn.provider_instance.fetch
      assert_equal %w[A B], records.map { |r| r["id"] }
    end
  end

  test "http_json provider blocks an SSRF endpoint" do
    conn = Connector.new(provider: "http_json", config: { "endpoint_url" => "http://169.254.169.254/latest" })
    error = assert_raises(Connectors::Error) { conn.provider_instance.fetch }
    assert_includes error.message, "blocked"
  end

  test "http_json provider raises on a non-2xx response" do
    conn = Connector.new(provider: "http_json", config: { "endpoint_url" => "https://api.example.com/c" })
    with_http(FakeResponse.new("503", "down")) do
      assert_raises(Connectors::Error) { conn.provider_instance.fetch }
    end
  end

  # --- source_connector provenance ---

  test "stamps the source connector on contacts it creates" do
    conn = connector
    stub_fetch(conn, [ { "id" => "CIF-7", "email" => "g@example.com", "name" => "Gamma" } ])
    Connectors::Sync.run(conn)
    assert_equal conn.id, Contact.find_by(external_id: "CIF-7").source_connector_id
  end

  test "stamps provenance on an update only when unset — keeps the first source" do
    first = connector
    Contact.create!(name: "Old", external_id: "CIF-9", email: "old@example.com", source_connector_id: first.id)
    other = connector
    stub_fetch(other, [ { "id" => "CIF-9", "email" => "new@example.com", "name" => "New" } ])
    Connectors::Sync.run(other)
    # Still attributed to the first connector that sourced it.
    assert_equal first.id, Contact.find_by(external_id: "CIF-9").source_connector_id

    # But a contact with no provenance gets stamped on update (backfill).
    Contact.create!(name: "Unsourced", external_id: "CIF-10", email: "u@example.com")
    stub_fetch(other, [ { "id" => "CIF-10", "email" => "u2@example.com", "name" => "U2" } ])
    Connectors::Sync.run(other)
    assert_equal other.id, Contact.find_by(external_id: "CIF-10").source_connector_id
  end
end
