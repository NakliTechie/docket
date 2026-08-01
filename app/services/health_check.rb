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
  STARTUP_GRACE = ENV.fetch("DOCKET_SWEEP_STARTUP_GRACE_SECONDS", 2.hours.to_i).to_i.seconds
  STORAGE_PROBE_TTL = 1.minute

  # Derive the monitored inventory from the same configuration Solid Queue
  # loads. A newly configured sweep cannot silently be omitted from /healthz.
  def self.recurring_inventory
    entries = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true).fetch("shared")
    entries.values.filter_map do |entry|
      name = entry["class"]
      schedule = entry["schedule"].to_s
      next unless name

      interval = case schedule
      when /every (\d+) minutes?/ then Regexp.last_match(1).to_i.minutes
      when /every hour/ then 1.hour
      when /every (\d+) hours?/ then Regexp.last_match(1).to_i.hours
      end
      [ name, interval ] if interval
    end.to_h.freeze
  end

  RECURRING = recurring_inventory

  Result = Struct.new(:ok, :checks, keyword_init: true) do
    def to_h = { status: ok ? "ok" : "degraded", checks: checks, checked_at: Time.current.iso8601 }
  end

  def self.call = new.call

  def self.booted_at = @booted_at ||= Time.current

  def self.cached_storage_probe(service)
    @storage_probe_mutex ||= Mutex.new
    @storage_probe_mutex.synchronize do
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      cached = @storage_probe_cache
      if cached && cached[:service_id] == service.object_id &&
          now - cached[:checked_at] < STORAGE_PROBE_TTL
        return cached[:result]
      end

      result = yield
      @storage_probe_cache = { service_id: service.object_id, checked_at: now, result: result }
      result
    end
  end

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
    service = ActiveStorage::Blob.service
    root = service.try(:root)
    return probe_remote_storage(service) if root.blank?

    { ok: File.writable?(root) }
  rescue StandardError => e
    { ok: false, error: e.class.name }
  end

  def probe_remote_storage(service)
    self.class.cached_storage_probe(service) do
      key = "docket-health/#{SecureRandom.hex(16)}"
      payload = "docket-storage-probe"
      uploaded = false
      begin
        service.upload(key, StringIO.new(payload), checksum: Digest::MD5.base64digest(payload))
        uploaded = true
        downloaded = service.download(key)
        service.delete(key)
        uploaded = false
        { ok: downloaded == payload }
      ensure
        service.delete(key) if uploaded
      end
    end
  end

  # H22: fail CLOSED on a dead queue database. `table_exists?` returns false
  # cleanly when the connection is fine but the table is absent (test/demo, a
  # legitimate "not configured"), and RAISES when the connection itself is dead.
  # Swallowing that raise made a down queue DB read as "not configured" (green);
  # instead let it propagate to the caller's rescue, which reports the check
  # failed. Only a truly-absent SolidQueue constant is "not available".
  def queue_available?(klass = nil)
    klass ||= defined?(SolidQueue::Job) ? SolidQueue::Job : nil
    return false if klass.nil?

    klass.table_exists?
  end

  def recurring_jobs
    stale = []
    never_run = []
    seen = {}
    ActsAsTenant.without_tenant do
      RECURRING.each do |name, interval|
        raw = Setting.where(tenant_id: nil, key: "job_last_success.#{name}").pick(:value)
        last = raw.present? ? (Time.zone.parse(raw) rescue nil) : nil
        seen[name] = last&.iso8601
        if last.present?
          stale << name if last < (interval * STALENESS_FACTOR).ago
        elsif Time.current > self.class.booted_at + STARTUP_GRACE
          stale << name
          never_run << name
        end
      end
    end
    { ok: stale.empty?, stale: stale, never_run: never_run, last_success: seen }
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
