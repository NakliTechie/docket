require "test_helper"

class ImportReconciliationTest < ActiveSupport::TestCase
  test "reports missing stale and locally conflicted source identities" do
    first = Imports::Session.new(source: "probe", dry_run: false)
    contact = nil
    first.process([ 1 ], stream: "contacts") do
      contact = first.sync(
        source_type: "contact", external_id: "C1", kind: "contacts",
        source_updated_at: "2025-01-01T00:00:00Z",
        attributes: { name: "Ravi", email: "reconcile@example.test", phone: "+911111111111" }
      ) { Contact.new }
    end
    first.finish!
    contact.update!(phone: "+922222222222")

    delta = Imports::Session.new(source: "probe", dry_run: false)
    delta.process([ 1 ], stream: "contacts") do
      delta.sync(
        source_type: "contact", external_id: "C1", kind: "contacts",
        source_updated_at: "2025-01-02T00:00:00Z",
        attributes: { name: "Ravi", email: "reconcile@example.test", phone: "+933333333333" }
      ) { Contact.new }
    end
    delta.finish!

    result = Imports::Reconciliation.call(
      source: "probe",
      inventory: {
        "contact" => [
          { "id" => "C1", "updated_at" => "2025-01-03T00:00:00Z" },
          { "id" => "C2", "updated_at" => "2025-01-03T00:00:00Z" }
        ]
      }
    )

    assert_not result[:ok]
    assert_equal [ "C2" ], result[:missing_in_docket].pluck("external_id")
    assert_equal [ "C1" ], result[:stale_source_rows].pluck("external_id")
    assert_equal [ "phone" ], result[:unresolved_conflicts].pluck(:field)
  end

  test "a complete matching inventory reconciles cleanly" do
    session = Imports::Session.new(source: "probe", dry_run: false)
    session.process([ 1 ], stream: "contacts") do
      session.sync(source_type: "contact", external_id: "C1", kind: "contacts",
                   attributes: { name: "Clean", email: "clean.reconcile@example.test" }) do
        Contact.new
      end
    end
    session.finish!

    result = Imports::Reconciliation.call(source: "probe", inventory: { "contact" => [ "C1" ] })

    assert result[:ok], result.inspect
    assert_equal({ source: 1, identities: 1, live_targets: 1 }, result[:counts])
  end

  test "a full inventory fails when a Docket identity is absent from the source" do
    session = Imports::Session.new(source: "probe", dry_run: false)
    session.process([ 1 ], stream: "contacts") do
      session.sync(source_type: "contact", external_id: "C1", kind: "contacts",
                   attributes: { name: "Missing upstream", external_id: "C1" }) do
        Contact.new
      end
    end
    session.finish!

    result = Imports::Reconciliation.call(source: "probe", inventory: { "contact" => [] })

    assert_not result[:ok]
    assert_equal [ "C1" ], result[:missing_in_source].pluck(:external_id)
  end
end
