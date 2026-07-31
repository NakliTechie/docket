require "test_helper"

class ImportSessionTest < ActiveSupport::TestCase
  test "a failed batch resumes after the last committed checkpoint" do
    seen = []
    first = Imports::Session.new(source: "probe", batch_size: 2, dry_run: false)
    error = assert_raises(RuntimeError) do
      first.process([ 1, 2, 3, 4, 5 ], stream: "rows") do |value|
        raise "interrupted" if value == 3
        seen << value
      end
    end
    assert_equal "interrupted", error.message
    assert_equal({ "offset" => 2 }, first.run.reload.checkpoint.fetch("rows"))
    assert_equal "failed", first.run.status

    resumed = Imports::Session.new(source: "probe", batch_size: 2, dry_run: false,
                                   resume_token: first.run.resume_token)
    resumed.process([ 1, 2, 3, 4, 5 ], stream: "rows") { |value| seen << value }
    resumed.finish!

    assert_equal [ 1, 2, 3, 4, 5 ], seen
    assert_equal "completed", resumed.run.reload.status
  end

  test "a source update does not overwrite a local edit" do
    initial = Imports::Session.new(source: "probe", dry_run: false)
    contact = nil
    initial.process([ 1 ], stream: "contacts") do
      contact = initial.sync(
        source_type: "contact", external_id: "C-1", kind: "contacts",
        attributes: { name: "Ravi", email: "ravi@probe.test", phone: "+911111111111" }
      ) { Contact.new }
    end
    initial.finish!
    contact.update!(phone: "+922222222222")

    delta = Imports::Session.new(source: "probe", dry_run: false)
    delta.process([ 1 ], stream: "contacts") do
      delta.sync(
        source_type: "contact", external_id: "C-1", kind: "contacts",
        attributes: { name: "Ravi", email: "ravi@probe.test", phone: "+933333333333" }
      ) { Contact.new }
    end
    delta.finish!

    assert_equal "+922222222222", contact.reload.phone
    assert_equal 1, delta.result.conflicts.size
    assert_equal "phone", ImportConflict.last.field
  end

  test "dry-run identities cannot autosave rolled-back targets" do
    session = Imports::Session.new(source: "probe", dry_run: true)
    session.process([ 1 ], stream: "contacts") do
      session.sync(source_type: "contact", external_id: "DRY-1", kind: "contacts",
                   attributes: { name: "Dry", email: "dry@probe.test" }) { Contact.new }
    end
    session.finish!

    assert_equal 1, session.result.created["contacts"]
    assert_not Contact.exists?(email: "dry@probe.test")
    assert_not ImportIdentity.exists?(external_id: "DRY-1")
    assert session.run.reload.dry_run?
  end

  test "only a clean applied run advances the next delta watermark" do
    preview = Imports::Session.new(source: "probe", source_instance: "watermark", dry_run: true)
    preview.process([ 1 ], stream: "rows") do
      preview.result.observe_watermark("2026-01-03T00:00:00Z")
    end
    preview.finish!

    after_preview = Imports::Session.new(source: "probe", source_instance: "watermark",
                                         dry_run: false)
    assert_nil after_preview.run.previous_watermark
    after_preview.result.observe_watermark("2026-01-02T00:00:00Z")
    after_preview.finish!

    erroneous = Imports::Session.new(source: "probe", source_instance: "watermark",
                                     dry_run: false)
    erroneous.result.observe_watermark("2026-01-05T00:00:00Z")
    erroneous.result.error!("one source row failed")
    erroneous.finish!

    delta = Imports::Session.new(source: "probe", source_instance: "watermark", dry_run: false)
    assert_equal Time.zone.parse("2026-01-02T00:00:00Z"), delta.run.previous_watermark
  end

  test "terminal imports with row errors cannot be resumed" do
    session = Imports::Session.new(source: "probe", dry_run: false)
    session.result.error!("invalid row")
    session.finish!

    error = assert_raises(Imports::Session::ResumeError) do
      Imports::Session.new(source: "probe", dry_run: false,
                           resume_token: session.run.resume_token)
    end
    assert_match "completed with errors", error.message
  end

  test "a live API resume uses the stable row cursor instead of a shifted offset" do
    cursor = ->(row) { row.slice("updated_at", "id") }
    rows = (1..4).map do |id|
      { "id" => id, "updated_at" => "2026-01-01T00:00:00Z" }
    end
    seen = []
    first = Imports::Session.new(source: "probe", source_instance: "api", batch_size: 2,
                                 dry_run: false)
    assert_raises(RuntimeError) do
      first.process(rows, stream: "records", cursor: cursor) do |row|
        raise "interrupted" if row["id"] == 3
        seen << row["id"]
      end
    end
    assert_equal({ "updated_at" => "2026-01-01T00:00:00Z", "id" => 2 },
                 first.run.reload.checkpoint.dig("records", "cursor"))

    shifted = [ { "id" => 0, "updated_at" => "2025-12-31T23:59:59Z" }, *rows.drop(1) ]
    resumed = Imports::Session.new(source: "probe", source_instance: "api", batch_size: 2,
                                   dry_run: false, resume_token: first.run.resume_token)
    resumed.process(shifted, stream: "records", cursor: cursor) { |row| seen << row["id"] }
    resumed.finish!

    assert_equal [ 1, 2, 3, 4 ], seen
  end
end
