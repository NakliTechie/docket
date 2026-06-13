require "test_helper"

# Connectors::Sync beyond contacts — Leads, Deals, Cases. Each dedupes on
# external_id, stamps source_connector_id, and resolves its mandatory shape
# (deals → a configured pipeline/stage; cases → a contact by email).
class Connectors::SyncTargetsTest < ActiveSupport::TestCase
  def stub_fetch(conn, records)
    fake = Object.new
    fake.define_singleton_method(:fetch) { records }
    conn.define_singleton_method(:provider_instance) { fake }
    conn
  end

  def connector(target:, mapping:, config: {})
    Connector.create!(name: "Pull #{target}", provider: "http_json", target: target,
                      config: { "endpoint_url" => "https://api.example.com/x" }.merge(config),
                      field_mapping: mapping)
  end

  # --- leads ---

  test "syncs leads with provenance + source=import, deduping by external_id" do
    conn = stub_fetch(
      connector(target: "leads", mapping: { "external_id" => "id", "email" => "email", "name" => "name", "company_name" => "company" }),
      [ { "id" => "L-1", "email" => "lead@x.com", "name" => "Lead One", "company" => "Acme" } ]
    )
    assert_difference("Lead.count", 1) { Connectors::Sync.run(conn) }
    lead = Lead.find_by(external_id: "L-1")
    assert_equal "lead@x.com", lead.email
    assert_equal "Acme", lead.company_name
    assert_equal conn.id, lead.source_connector_id
    assert_equal "import", lead.source

    stub_fetch(conn, [ { "id" => "L-1", "email" => "lead2@x.com", "name" => "Lead One", "company" => "Acme" } ])
    assert_no_difference("Lead.count") { Connectors::Sync.run(conn) }
    assert_equal "lead2@x.com", Lead.find_by(external_id: "L-1").email
  end

  # --- deals ---

  test "syncs deals into the configured pipeline's first open stage" do
    pipeline = Pipeline.new(name: "Sync Funnel")
    pipeline.pipeline_stages.build([
      { name: "New", position: 0, probability: 10 },
      { name: "Won", position: 1, probability: 100, is_won: true }
    ])
    pipeline.save!
    new_stage = pipeline.pipeline_stages.find_by(name: "New")

    conn = stub_fetch(
      connector(target: "deals", mapping: { "external_id" => "id", "name" => "title", "value" => "amount" },
                config: { "default_pipeline_id" => pipeline.id }),
      [ { "id" => "D-1", "title" => "Big deal", "amount" => "5000" } ]
    )
    assert_difference("Deal.count", 1) { Connectors::Sync.run(conn) }
    deal = Deal.find_by(external_id: "D-1")
    assert_equal "Big deal", deal.name
    assert_equal 500_000, deal.value_cents # value= setter, rupees → cents
    assert_equal new_stage.id, deal.pipeline_stage_id # first non-terminal stage
    assert_equal conn.id, deal.source_connector_id
  end

  # --- cases ---

  test "syncs cases, resolving the contact by email and deduping by external_id" do
    conn = stub_fetch(
      connector(target: "cases", mapping: { "external_id" => "id", "subject" => "subj", "contact_email" => "email" }),
      [ { "id" => "T-1", "subj" => "Cannot log in", "email" => "person@x.com" } ]
    )
    assert_difference("Case.count", 1) { Connectors::Sync.run(conn) }
    kase = Case.find_by(external_id: "T-1")
    assert_equal "Cannot log in", kase.subject
    assert_equal "person@x.com", kase.contact.email
    assert_equal conn.id, kase.source_connector_id

    stub_fetch(conn, [ { "id" => "T-1", "subj" => "Login fixed", "email" => "person@x.com" } ])
    assert_no_difference("Case.count") { Connectors::Sync.run(conn) }
    assert_equal "Login fixed", Case.find_by(external_id: "T-1").subject
  end

  # --- validation ---

  test "leads/deals/cases are valid sync targets" do
    assert_equal %w[contacts leads deals cases], Connector::TARGETS
  end

  test "a deals connector is invalid without a default_pipeline_id" do
    c = Connector.new(name: "D", provider: "http_json", target: "deals", field_mapping: { "external_id" => "id" })
    assert_not c.valid?
    assert c.errors[:config].any?
  end

  test "a cases connector is invalid without subject + contact_email mapped" do
    incomplete = Connector.new(name: "C", provider: "http_json", target: "cases", field_mapping: { "external_id" => "id" })
    assert_not incomplete.valid?
    assert incomplete.errors[:field_mapping].any?

    complete = Connector.new(name: "C2", provider: "http_json", target: "cases",
                             config: { "endpoint_url" => "https://api.example.com/x" },
                             field_mapping: { "external_id" => "id", "subject" => "s", "contact_email" => "e" })
    assert complete.valid?, complete.errors.full_messages.to_sentence
  end
end
