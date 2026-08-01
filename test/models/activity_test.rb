require "test_helper"

class ActivityTest < ActiveSupport::TestCase
  test "requires a title" do
    activity = Activity.new(subject: contacts(:asha), owner: users(:sales))
    refute activity.valid?
    activity.title = "Call Asha"
    assert activity.valid?
  end

  test "subject must be an allowlisted type" do
    refute Activity.new(title: "x", subject_type: "User", subject_id: users(:sales).id).valid?
    assert Activity.new(title: "x", subject: contacts(:asha)).valid?
  end

  test "kind and status default to task/open" do
    activity = Activity.create!(title: "x", subject: contacts(:asha))
    assert activity.kind_task?
    assert activity.status_open?
  end

  test "complete! marks it done and stamps completed_at" do
    activity = Activity.create!(title: "x", subject: contacts(:asha), kind: :call)
    activity.complete!
    assert activity.status_done?
    assert activity.completed_at.present?
  end

  test "overdue? is true only for an open, past-due activity" do
    activity = Activity.create!(title: "x", subject: contacts(:asha), due_at: 1.hour.ago)
    assert activity.overdue?
    activity.complete!
    refute activity.overdue?, "a done activity is never overdue"
  end

  test "overdue scope selects open past-due activities" do
    past = Activity.create!(title: "late", subject: contacts(:asha), due_at: 2.hours.ago)
    Activity.create!(title: "future", subject: contacts(:asha), due_at: 2.hours.from_now)
    assert_includes Activity.overdue, past
    assert_equal 1, Activity.overdue.count
  end

  test "recent_first orders due activities first, then undated by recency" do
    dated = Activity.create!(title: "dated", subject: contacts(:asha), due_at: 1.day.from_now)
    undated = Activity.create!(title: "undated", subject: contacts(:asha))
    assert_equal [ dated, undated ], Activity.recent_first.to_a.first(2)
  end

  test "is tenant-scoped and audited on create" do
    assert_difference "AuditEntry.count", 1 do
      Activity.create!(title: "x", subject: contacts(:asha))
    end
    assert_equal tenants(:primary).id, Activity.last.tenant_id
  end
end
