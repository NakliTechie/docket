require "test_helper"

class RoutingRuleSchedulerJobTest < ActiveJob::TestCase
  test "fans out only to tenants with the service desk feature" do
    RoutingRule.create!(
      name: "Escalate stale", trigger_type: :elapsed_time, if_status: :new,
      after_minutes: 1, use_business_hours: false, then_priority: :urgent
    )
    kase = cases(:pension_case)
    kase.update_columns(status_changed_at: 2.minutes.ago)
    tenants(:primary).set_feature!("service_desk", false)

    assert_no_difference "RoutingRuleExecution.count" do
      RoutingRuleSchedulerJob.perform_now
    end
    refute kase.reload.priority_urgent?
  end

  test "records an operator-visible sweep heartbeat" do
    ActsAsTenant.without_tenant do
      Setting.where(tenant_id: nil, key: "job_last_success.RoutingRuleSchedulerJob").delete_all
    end

    RoutingRuleSchedulerJob.perform_now

    heartbeat = ActsAsTenant.without_tenant do
      Setting.where(tenant_id: nil, key: "job_last_success.RoutingRuleSchedulerJob").pick(:value)
    end
    assert heartbeat.present?
  end
end
