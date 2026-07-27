# What an operator needs at 2am. Before this the only signal was Rails' /up,
# which proves the process booted and nothing else: not that the database is
# reachable, not that the queue is draining, not that the recurring sweeps have
# run since Tuesday.
#
# Deliberately dependency-free — no Prometheus, no APM. It reads what the app
# already knows and answers in JSON.
class HealthCheck
  # A sweep is stale when it has not completed in this multiple of its interval.
  # Generous: a late sweep is normal, a sweep that has not run in hours is not.
  STALENESS_FACTOR = 4

  # name => how often config/recurring.yml says it runs.
  RECURRING = {
    "SlaBreachSweepJob" => 5.minutes,
    "ConnectorSchedulerJob" => 5.minutes,
    "SequenceRunnerJob" => 1.hour,
    "SessionSweepJob" => 1.hour,
    "DecisioningRunJob" => 1.hour
  }.freeze

  Result = Struct.new(:ok, :checks, keyword_init: true) do
    def to_h = { status: ok ? "ok" : "degraded", checks: checks, checked_at: Time.current.iso8601 }
  end

  def self.call = new.call

  def call
    checks = {
      database: database,
      queue: queue,
      storage: storage,
      recurring_jobs: recurring_jobs,
      failed_jobs: failed_jobs
    }
    Result.new(ok: checks.values.all? { |c| c[:ok] }, checks: checks)
  end

  private

  def database
    ActiveRecord::Base.connection.select_value("SELECT 1")
    { ok: true }
  rescue StandardError => e
    { ok: false, error: e.class.name }
  end

  # The queue lives in its own database; the app can be perfectly healthy while
  # nothing is being processed.
  # "Not configured in this environment" is a different answer from "broken".
  # The test and demo databases have no queue tables; reporting that as a
  # failure would make /healthz permanently red where it is meaningless.
  def queue
    return { ok: true, note: "not configured" } unless queue_available?

    { ok: true, pending: SolidQueue::Job.where(finished_at: nil).count }
  rescue StandardError => e
    { ok: false, error: e.class.name }
  end

  def storage
    root = ActiveStorage::Blob.service.try(:root)
    return { ok: true, note: "not a disk service" } if root.blank?

    { ok: File.writable?(root) }
  rescue StandardError => e
    { ok: false, error: e.class.name }
  end

  def queue_available?(klass = nil)
    klass ||= defined?(SolidQueue::Job) ? SolidQueue::Job : nil
    return false if klass.nil?

    klass.table_exists?
  rescue StandardError
    false
  end

  def recurring_jobs
    stale = []
    seen = {}
    ActsAsTenant.without_tenant do
      RECURRING.each do |name, interval|
        raw = Setting.where(tenant_id: nil, key: "job_last_success.#{name}").pick(:value)
        last = raw.present? ? (Time.zone.parse(raw) rescue nil) : nil
        seen[name] = last&.iso8601
        # Never-run is not reported as failure: a fresh deployment has not had a
        # chance yet, and crying wolf on boot trains operators to ignore this.
        stale << name if last.present? && last < (interval * STALENESS_FACTOR).ago
      end
    end
    { ok: stale.empty?, stale: stale, last_success: seen }
  rescue StandardError => e
    { ok: false, error: e.class.name }
  end

  def failed_jobs
    return { ok: true, note: "not configured" } unless queue_available?(SolidQueue::FailedExecution)

    count = SolidQueue::FailedExecution.count
    { ok: count.zero?, count: count }
  rescue StandardError => e
    { ok: false, error: e.class.name }
  end
end
