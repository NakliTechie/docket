require "test_helper"

class BusinessCalendarTest < ActiveSupport::TestCase
  test "requires at least one non-overlapping working window" do
    calendar = BusinessCalendar.new(name: "Support", time_zone: "UTC")
    assert_not calendar.valid?
    assert calendar.errors[:business_calendar_windows].present?

    calendar.business_calendar_windows.build(weekday: 1, starts_minute: 540, ends_minute: 1020)
    calendar.business_calendar_windows.build(weekday: 1, starts_minute: 900, ends_minute: 1080)
    assert_not calendar.valid?
    assert calendar.business_calendar_windows.any? { |window| window.errors[:base].present? }
  end

  test "rejects untouched nested form rows even when the closed checkbox submits zero" do
    calendar = BusinessCalendar.new(
      name: "Support", time_zone: "UTC",
      business_calendar_windows_attributes: {
        "0" => { weekday: "1", starts_at: "09:00", ends_at: "17:00" },
        "1" => { weekday: "", starts_at: "", ends_at: "" }
      },
      business_calendar_exceptions_attributes: {
        "0" => { on_date: "", name: "", closed: "0", starts_at: "", ends_at: "" }
      }
    )

    assert calendar.save
    assert_equal 1, calendar.business_calendar_windows.size
    assert_empty calendar.business_calendar_exceptions
  end

  test "only one calendar is the tenant default" do
    first = build_calendar(name: "First", is_default: true)
    second = build_calendar(name: "Second", is_default: true)

    assert_not first.reload.is_default?
    assert second.reload.is_default?
    entry = AuditEntry.where(action: "business_calendar.update",
                             auditable_type: "BusinessCalendar", auditable_id: first.id).last
    assert_equal [ true, false ], entry.changeset["is_default"]
  end

  test "validates closed and custom-hours exceptions" do
    calendar = build_calendar
    closed = calendar.business_calendar_exceptions.create!(
      on_date: Date.new(2026, 8, 3), name: "Holiday", closed: true
    )
    assert closed.closed?

    custom = calendar.business_calendar_exceptions.new(
      on_date: Date.new(2026, 8, 4), name: "Short day", closed: false,
      starts_minute: 900, ends_minute: 720
    )
    assert_not custom.valid?
  end

  private

  def build_calendar(name: "Support", is_default: false)
    calendar = BusinessCalendar.new(name: name, time_zone: "UTC", is_default: is_default)
    calendar.business_calendar_windows.build(weekday: 1, starts_minute: 540, ends_minute: 1020)
    calendar.save!
    calendar
  end
end
