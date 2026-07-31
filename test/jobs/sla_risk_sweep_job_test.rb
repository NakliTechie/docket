require "test_helper"

class SlaRiskSweepJobTest < ActiveJob::TestCase
  test "notifies once inside the business-minute risk window" do
    kase = cases(:assigned_case)
    kase.update_columns(first_response_due_at: 30.minutes.from_now,
                        resolution_due_at: 2.hours.from_now,
                        first_responded_at: nil,
                        first_response_breached: false,
                        resolution_breached: false)
    Setting.set("sla_risk_minutes", 60)

    assert_difference "Notification.kind_sla_risk.count", 1 do
      SlaRiskSweepJob.perform_now
    end
    assert_no_difference "Notification.count" do
      SlaRiskSweepJob.perform_now
    end

    notification = Notification.kind_sla_risk.find_by!(notifiable: kase)
    assert_equal users(:agent_a), notification.user
    assert notification.severity_warning?
    assert_equal 1, notification.occurrences
  ensure
    Setting.unset("sla_risk_minutes")
  end
end
