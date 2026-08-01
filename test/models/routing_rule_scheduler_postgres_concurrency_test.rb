require "test_helper"

class RoutingRuleSchedulerPostgresConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @postgres = ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    next unless @postgres

    @tenant = Tenant.find_by!(slug: "primary")
    @audit_start_id = AuditEntry.maximum(:id).to_i
    ActsAsTenant.with_tenant(@tenant) do
      suffix = SecureRandom.hex(6)
      @contact = Contact.create!(name: "Automation race contact #{suffix}",
                                 email: "automation-race-#{suffix}@example.test")
      @kase = Case.create!(subject: "Automation race", contact: @contact)
      @kase.update_columns(status_changed_at: 2.hours.ago)
      @rule = RoutingRule.create!(
        name: "Automation race #{SecureRandom.hex(4)}", trigger_type: :elapsed_time,
        if_status: :new, after_minutes: 1, use_business_hours: false,
        then_priority: :urgent
      )
    end
  end

  teardown do
    next unless @postgres

    ActsAsTenant.with_tenant(@tenant) do
      RoutingRuleExecution.where(case_id: @kase&.id).delete_all if @kase
      SlaClockEvent.where(case_id: @kase&.id).delete_all if @kase
      Case.with_deleted.where(id: @kase.id).delete_all if @kase
      RoutingRule.where(id: @rule.id).delete_all if @rule
      Contact.with_deleted.where(id: @contact.id).delete_all if @contact
      AuditEntry.where("id > ?", @audit_start_id).delete_all
    end
  end

  test "overlapping scheduler sessions apply one action and create one receipt" do
    return assert true unless @postgres

    ready = Queue.new
    start = Queue.new
    results = Queue.new
    errors = Queue.new
    backend_pids = Queue.new
    at = Time.current

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ActsAsTenant.with_tenant(@tenant) do
            backend_pids << connection.select_value("SELECT pg_backend_pid()")
            ready << true
            start.pop
            results << ScheduledCaseRouting.execute!(@rule, @kase, at: at, calendar: nil)
          rescue StandardError => error
            errors << error
          end
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)

    assert_empty drain(errors)
    assert_equal 2, drain(backend_pids).uniq.size
    assert_equal [ false, true ], drain(results).sort_by(&:to_s)
    assert_equal 1, RoutingRuleExecution.where(routing_rule: @rule, case: @kase).count
    assert @kase.reload.priority_urgent?
  end

  private

  def drain(queue)
    queue.size.times.map { queue.pop }
  end
end
