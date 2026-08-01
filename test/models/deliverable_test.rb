require "test_helper"

class DeliverableTest < ActiveSupport::TestCase
  setup do
    @deal = Deal.create!(name: "RFQ machining", pipeline: pipelines(:sales),
                         contact: contacts(:asha), organisation: organisations(:dpg), owner: users(:admin))
  end

  def build_deliverable(**attrs)
    Deliverable.new({ deal: @deal, title: "Feasibility report",
                      scope_items: [ { "description" => "Machine 20 brackets", "quantity" => 20, "unit" => "pcs" } ] }.merge(attrs))
  end

  test "valid with a deal, title and well-formed scope" do
    assert build_deliverable.valid?
  end

  test "title is required" do
    d = build_deliverable(title: "")
    refute d.valid?
    assert d.errors[:title].present?
  end

  test "scope entry needs a description" do
    d = build_deliverable(scope_items: [ { "quantity" => 5 } ])
    refute d.valid?
    assert_match(/description/, d.errors[:scope_items].join)
  end

  test "scope_entries normalizes to the allowed keys as symbols" do
    d = build_deliverable(scope_items: [ { "description" => "X", "quantity" => 2, "unit" => "pcs", "price" => 999 } ])
    entry = d.scope_entries.sole
    assert_equal %i[description quantity unit], entry.keys.sort
    refute entry.key?(:price), "engineering scope never carries price"
  end

  test "an issued deliverable is frozen — content cannot change" do
    d = build_deliverable
    d.save!
    d.update_columns(status: Deliverable.statuses[:issued], issued_at: Time.current)

    d.reload.title = "Tampered"
    refute d.valid?
    assert_match(/frozen/, d.errors[:base].join)
  end

  test "an issued deliverable may still be soft-deleted" do
    d = build_deliverable
    d.save!
    d.update_columns(status: Deliverable.statuses[:issued], issued_at: Time.current)
    assert d.reload.destroy, "soft-delete stamps deleted_at without touching frozen content"
    assert d.deleted?
  end

  test "cites study work items without growing WorkLink's allowlist" do
    d = build_deliverable
    d.save!
    d.studies << work_items(:pep_one)
    assert_includes d.reload.studies, work_items(:pep_one)
  end

  test "belongs to its tenant and is audited on create" do
    d = build_deliverable
    assert_difference "AuditEntry.count", 1 do
      d.save!
    end
    assert_equal tenants(:primary).id, d.tenant_id
  end
end
