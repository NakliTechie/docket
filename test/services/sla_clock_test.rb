require "test_helper"

class SlaClockTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @calendar = BusinessCalendar.new(name: "Support", time_zone: "UTC", is_default: true)
    (1..5).each do |weekday|
      @calendar.business_calendar_windows.build(
        weekday: weekday, starts_minute: 540, ends_minute: 1020
      )
    end
    @calendar.save!
    @policy = SlaPolicy.create!(name: "Clock test", business_calendar: @calendar)
    @policy.sla_targets.create!(
      priority: :normal, first_response_minutes: 60, resolution_minutes: 180
    )
  end

  test "creates business-time deadlines and an append-only event ledger" do
    travel_to Time.utc(2026, 8, 3, 16, 30) do
      kase = create_case

      assert_equal Time.utc(2026, 8, 4, 9, 30), kase.first_response_due_at
      assert_equal Time.utc(2026, 8, 4, 11, 30), kase.resolution_due_at
      assert_equal %w[first_response resolution], kase.sla_clock_events.order(:id).pluck(:clock_kind)
      assert kase.sla_clock_events.all?(&:event_kind_started?)
      assert_raises(ActiveRecord::ReadOnlyRecord) { kase.sla_clock_events.first.destroy! }
    end
  end

  test "pauses and resumes the resolution clock while waiting on the customer" do
    travel_to Time.utc(2026, 8, 3, 9, 0) do
      kase = create_case
      kase.transition_to!(:in_progress)
      travel 60.minutes
      kase.transition_to!(:waiting_on_customer)

      assert_nil kase.resolution_due_at
      assert_equal 120, kase.resolution_remaining_minutes
      assert_equal "paused", kase.sla_clock_events.order(:id).last.event_kind

      travel 2.hours
      kase.transition_to!(:in_progress)
      assert_equal Time.utc(2026, 8, 3, 14, 0), kase.resolution_due_at
      assert_nil kase.resolution_paused_at
      assert_nil kase.resolution_remaining_minutes
      assert_equal "resumed", kase.sla_clock_events.order(:id).last.event_kind
    end
  end

  test "resolve while paused stops the clock without losing compliance history" do
    travel_to Time.utc(2026, 8, 3, 9, 0) do
      kase = create_case
      kase.transition_to!(:in_progress)
      kase.transition_to!(:waiting_on_customer)
      travel 1.day
      kase.transition_to!(:resolved)

      assert_nil kase.resolution_paused_at
      assert_nil kase.resolution_remaining_minutes
      assert_operator kase.resolution_due_at, :>, kase.resolved_at
      assert_equal "stopped", kase.sla_clock_events.order(:id).last.event_kind
    end
  end

  test "reopening starts a fresh full resolution clock" do
    travel_to Time.utc(2026, 8, 3, 9, 0) do
      kase = create_case
      kase.transition_to!(:in_progress)
      kase.transition_to!(:resolved)
      kase.transition_to!(:reopened)

      assert_equal Time.utc(2026, 8, 3, 12, 0), kase.resolution_due_at
      event = kase.sla_clock_events.order(:id).last
      assert event.event_kind_started?
      assert_equal "reopened", event.reason
      assert_equal 180, event.remaining_minutes
    end
  end

  private

  def create_case
    Case.create!(subject: "Clock", contact: contacts(:asha), sla_policy: @policy)
  end
end
