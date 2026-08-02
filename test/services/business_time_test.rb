require "test_helper"

class BusinessTimeTest < ActiveSupport::TestCase
  setup do
    @calendar = BusinessCalendar.new(name: "Support", time_zone: "UTC")
    (1..5).each do |weekday|
      @calendar.business_calendar_windows.build(
        weekday: weekday, starts_minute: 540, ends_minute: 1020
      )
    end
    @calendar.save!
  end

  test "adds minutes across working-day boundaries" do
    from = Time.utc(2026, 8, 3, 16, 30) # Monday

    assert_equal Time.utc(2026, 8, 4, 10, 30),
                 BusinessTime.add_minutes(calendar: @calendar, from: from, minutes: 120)
  end

  test "skips closed holidays and honors custom exception hours" do
    @calendar.business_calendar_exceptions.create!(
      on_date: Date.new(2026, 8, 4), name: "Holiday", closed: true
    )
    @calendar.business_calendar_exceptions.create!(
      on_date: Date.new(2026, 8, 5), name: "Short day", closed: false,
      starts_minute: 720, ends_minute: 900
    )

    from = Time.utc(2026, 8, 3, 16, 30)
    assert_equal Time.utc(2026, 8, 5, 13, 30),
                 BusinessTime.add_minutes(calendar: @calendar, from: from, minutes: 120)
  end

  test "counts only business minutes between timestamps" do
    from = Time.utc(2026, 8, 7, 16, 0) # Friday
    finish = Time.utc(2026, 8, 10, 10, 30) # Monday

    assert_equal 150,
                 BusinessTime.minutes_between(calendar: @calendar, from: from, to: finish)
  end

  test "uses the calendar time zone across daylight-saving changes" do
    @calendar.update!(time_zone: "Eastern Time (US & Canada)")
    from = Time.utc(2026, 10, 30, 20, 30) # Friday 16:30 EDT

    # The weekend changes to EST; Monday 10:30 local is 15:30 UTC.
    assert_equal Time.utc(2026, 11, 2, 15, 30),
                 BusinessTime.add_minutes(calendar: @calendar, from: from, minutes: 120)
  end

  test "finds the next opening when a timestamp falls outside business hours" do
    friday_evening = Time.utc(2026, 8, 7, 19, 0)

    assert_equal Time.utc(2026, 8, 10, 9, 0),
                 BusinessTime.next_opening(calendar: @calendar, at: friday_evening)
  end
end
