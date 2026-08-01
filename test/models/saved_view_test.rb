require "test_helper"

class SavedViewTest < ActiveSupport::TestCase
  test "sanitizes filters and validates resource context" do
    view = SavedView.new(
      user: users(:admin), resource_type: "cases", name: " Urgent inbox ",
      filters: { priority: "urgent", unsafe: "ignored" }
    )
    view.filters = SavedView.sanitize_filters(view.resource_type, view.filters)

    assert view.save
    assert_equal "Urgent inbox", view.name
    assert_equal({ "priority" => "urgent" }, view.filters)

    work_view = SavedView.new(user: users(:admin), resource_type: "work_items", name: "Mine", filters: {})
    refute work_view.valid?
    assert_includes work_view.errors[:context_id], "is required for work items"
  end

  test "work views cannot point at another tenant's project" do
    view = SavedView.new(
      user: users(:admin), resource_type: "work_items", name: "Foreign",
      context_id: projects(:acme_proj).id, filters: {}
    )

    refute view.valid?
    assert_includes view.errors[:context_id], "must reference a project in the same tenant"
  end

  test "database indexes enforce owner and context uniqueness" do
    now = Time.current
    row = {
      tenant_id: tenants(:primary).id, user_id: users(:admin).id,
      resource_type: "cases", context_id: nil, name: "Race safe", filters: {},
      created_at: now, updated_at: now
    }
    SavedView.insert_all!([ row ])

    assert_raises(ActiveRecord::RecordNotUnique) { SavedView.insert_all!([ row ]) }
  end
end
