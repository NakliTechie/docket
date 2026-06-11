require "test_helper"

class ActivityReportTest < ActiveSupport::TestCase
  def report
    ActivityReport.new(from: Date.current, to: Date.current)
  end

  test "breach_events counts a flag flip to true, not its later un-flagging (L)" do
    baseline = report.stats[:sla_breaches]

    kase = Case.create!(subject: "Breached", contact: contacts(:asha), sla_policy: sla_policies(:standard))
    kase.update_columns(resolution_due_at: 2.hours.ago)
    SlaBreachSweepJob.perform_now # flips resolution_breached false -> true (audited)
    Current.set(actor: users(:admin)) { kase.reload.update!(resolution_breached: false) } # un-flag (audited)

    # Old LIKE row-count caught both rows (+2); only the true-flip is an event.
    assert_equal baseline + 1, report.stats[:sla_breaches]
  end

  test "reports keep counting a case created in range after it is soft-deleted (L)" do
    baseline = report.stats[:cases_created]
    kase = Case.create!(subject: "Created then deleted", contact: contacts(:asha))
    Current.set(actor: users(:admin)) { kase.destroy } # soft-delete

    assert_equal baseline + 1, report.stats[:cases_created]
  end

  test "logins is memoized" do
    r = report
    assert_same r.logins, r.logins
  end
end
