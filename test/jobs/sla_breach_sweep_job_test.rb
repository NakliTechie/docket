require "test_helper"

class SlaBreachSweepJobTest < ActiveJob::TestCase
  test "flags overdue first response and resolution, audited, once" do
    kase = cases(:pension_case)
    kase.update_columns(first_response_due_at: 2.hours.ago, resolution_due_at: 1.hour.ago)

    assert_difference "AuditEntry.count", 2 do
      SlaBreachSweepJob.perform_now
    end
    kase.reload
    assert kase.first_response_breached
    assert kase.resolution_breached

    assert_no_difference "AuditEntry.count" do
      SlaBreachSweepJob.perform_now
    end
  end

  test "does not flag cases that responded in time" do
    kase = cases(:pension_case)
    kase.update_columns(first_response_due_at: 2.hours.ago, first_responded_at: 3.hours.ago)
    SlaBreachSweepJob.perform_now
    refute kase.reload.first_response_breached
  end

  test "does not flag cases resolved on time" do
    kase = cases(:resolved_case) # resolved_at 2.days.ago
    kase.update_columns(resolution_due_at: 2.hours.ago) # due well after it was resolved
    SlaBreachSweepJob.perform_now
    refute kase.reload.resolution_breached
  end

  test "flags a case that went overdue before it was resolved, even though it is now resolved (M18)" do
    kase = cases(:resolved_case) # resolved_at 2.days.ago
    kase.update_columns(resolution_due_at: 3.days.ago, resolution_breached: false) # resolved late
    assert_difference "AuditEntry.count", 1 do
      SlaBreachSweepJob.perform_now
    end
    assert kase.reload.resolution_breached
  end
end
