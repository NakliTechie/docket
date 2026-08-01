require "test_helper"

# The enrollment row lock is meaningful only on the production adapter. Keep
# this test non-transactional so each worker owns an independent committed
# PostgreSQL session, matching overlapping recurring sweeps in production.
class SequenceEnrollmentPostgresConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @postgres = ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
    next unless @postgres

    @tenant = Tenant.find_by!(slug: "primary")
    @audit_start_id = AuditEntry.maximum(:id).to_i
    ActsAsTenant.with_tenant(@tenant) do
      @sequence = Sequence.new(name: "Concurrent sequence #{SecureRandom.hex(4)}")
      @sequence.sequence_steps.build(
        position: 0, delay_days: 0, subject: "Now", body: "First"
      )
      @sequence.sequence_steps.build(
        position: 1, delay_days: 1, subject: "Tomorrow", body: "Second"
      )
      @sequence.save!
      @lead = Lead.create!(
        name: "Concurrent recipient",
        email: "sequence-race-#{SecureRandom.hex(6)}@example.test"
      )
      @enrollment = @sequence.enroll!(@lead)
    end
  end

  teardown do
    next unless @postgres

    ActsAsTenant.with_tenant(@tenant) do
      SequenceDelivery.where(sequence_enrollment_id: @enrollment.id).delete_all
      SequenceEnrollment.with_deleted.where(id: @enrollment.id).delete_all
      SequenceStep.with_deleted.where(sequence_id: @sequence.id).delete_all
      Sequence.with_deleted.where(id: @sequence.id).delete_all
      Lead.with_deleted.where(id: @lead.id).delete_all
      AuditEntry.where("id > ?", @audit_start_id).delete_all
    end
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  test "two sessions create one receipt and advance the enrollment once" do
    return assert true unless @postgres

    ready = Queue.new
    start = Queue.new
    results = Queue.new
    errors = Queue.new
    backend_pids = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          ActsAsTenant.with_tenant(@tenant) do
            enrollment = SequenceEnrollment.find(@enrollment.id)
            backend_pids << connection.select_value("SELECT pg_backend_pid()")
            ready << true
            start.pop
            results << enrollment.advance!
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
    assert_equal 2, drain(backend_pids).uniq.size, "the race must use two database sessions"
    assert_equal [ false, true ], drain(results).sort_by(&:to_s)

    @enrollment.reload
    assert_equal 1, @enrollment.current_step_position
    assert_equal @sequence.ordered_steps.second, @enrollment.current_step
    assert @enrollment.status_active?
    assert_operator @enrollment.next_run_at, :>, Time.current
    assert_equal 1, @enrollment.sequence_deliveries.count
    assert_equal @sequence.ordered_steps.first,
                 @enrollment.sequence_deliveries.first.sequence_step
  end

  private

  def drain(queue)
    queue.size.times.map { queue.pop }
  end
end
