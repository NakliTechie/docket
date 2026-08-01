require "test_helper"

# R1: an operator at 2am previously had `curl /up` (proves the process booted)
# and `docker logs`. They could not tell whether the queue was draining or
# whether the SLA sweep had run since Tuesday.
class HealthCheckTest < ActionDispatch::IntegrationTest
  def replace_singleton_method(target, name, replacement)
    original = target.method(name)
    target.define_singleton_method(name, replacement)
    yield
  ensure
    target.define_singleton_method(name, original)
  end

  def stamp(job, at)
    ActsAsTenant.without_tenant do
      Setting.find_or_initialize_by(tenant_id: nil, key: "job_last_success.#{job}")
             .update!(value: at.iso8601)
    end
  end

  test "a healthy deployment answers 200 with every check named" do
    get "/healthz"
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "ok", body["status"]
    assert_equal %w[database queue storage recurring_jobs failed_jobs].sort,
                 body["checks"].keys.sort
    assert body.dig("checks", "database", "ok")
  end

  test "it is reachable without signing in" do
    get "/healthz"
    assert_response :success, "a load balancer cannot authenticate"
  end

  # H22: a DOWN queue database must FAIL the check, not read as "not configured".
  # table_exists? returns false cleanly when the table is merely absent (test/demo);
  # it RAISES when the connection is dead, and that must turn the check red.
  test "a dead queue database fails the check, not 'not configured'" do
    SolidQueue::Job.define_singleton_method(:table_exists?) do
      raise ActiveRecord::ConnectionNotEstablished, "queue db down"
    end
    get "/healthz"
    assert_response :service_unavailable
    queue = JSON.parse(response.body).dig("checks", "queue")
    assert_equal false, queue["ok"], "a dead queue DB is a failure, not 'not configured'"
    assert queue["error"].present?, "reports the exception class only"
  ensure
    SolidQueue::Job.singleton_class.send(:remove_method, :table_exists?)
  end

  test "a sweep that has not run in hours turns the check red" do
    stamp("SlaBreachSweepJob", 6.hours.ago) # runs every 5 minutes
    get "/healthz"

    assert_response :service_unavailable, "silent job death is the failure mode this exists for"
    body = JSON.parse(response.body)
    assert_equal "degraded", body["status"]
    assert_includes body.dig("checks", "recurring_jobs", "stale"), "SlaBreachSweepJob"
  end

  test "a recently-run sweep is healthy and reports when it last succeeded" do
    stamp("SlaBreachSweepJob", 1.minute.ago)
    get "/healthz"

    assert_response :success
    assert JSON.parse(response.body).dig("checks", "recurring_jobs", "last_success", "SlaBreachSweepJob").present?
  end

  test "a never-run sweep stays healthy during the explicit startup grace" do
    get "/healthz"
    assert_response :success,
                    "a fresh deployment has not had a chance yet; crying wolf on boot trains operators to ignore this"
  end

  test "a never-run sweep degrades health after the startup grace" do
    replacement = -> { HealthCheck::STARTUP_GRACE.ago - 1.minute }
    replace_singleton_method(HealthCheck, :booted_at, replacement) do
      get "/healthz"
    end

    assert_response :service_unavailable
    check = JSON.parse(response.body).dig("checks", "recurring_jobs")
    assert_includes check["never_run"], "SlaBreachSweepJob"
    assert_includes check["stale"], "SlaBreachSweepJob"
  end

  test "a non-disk storage service is verified by upload download and delete" do
    stored = {}
    service = Object.new
    service.define_singleton_method(:upload) { |key, io, **| stored[key] = io.read }
    service.define_singleton_method(:download) { |key| stored.fetch(key) }
    service.define_singleton_method(:delete) { |key| stored.delete(key) }

    replace_singleton_method(ActiveStorage::Blob, :service, -> { service }) do
      get "/healthz"
    end

    assert_response :success
    assert JSON.parse(response.body).dig("checks", "storage", "ok")
    assert_empty stored, "the health probe must clean up its object"
  end

  test "a failing non-disk storage service degrades health without leaking its message" do
    service = Object.new
    service.define_singleton_method(:upload) { |*, **| raise IOError, "secret bucket name" }

    replace_singleton_method(ActiveStorage::Blob, :service, -> { service }) do
      get "/healthz"
    end

    assert_response :service_unavailable
    storage = JSON.parse(response.body).dig("checks", "storage")
    assert_equal "IOError", storage["error"]
    refute_includes response.body, "secret bucket name"
  end

  test "it leaks nothing beyond check names and up/down" do
    stamp("SlaBreachSweepJob", 6.hours.ago)
    get "/healthz"

    body = response.body
    refute_match(/password|secret|token|SELECT|postgres:\/\//i, body)
    refute_match Rails.application.credentials.secret_key_base.to_s[0, 12], body if Rails.application.credentials.secret_key_base
  end

  test "sweeps stamp their own success" do
    ActsAsTenant.without_tenant do
      Setting.where(tenant_id: nil, key: "job_last_success.SlaBreachSweepJob").delete_all
    end

    SlaBreachSweepJob.new.perform

    recorded = ActsAsTenant.without_tenant do
      Setting.where(tenant_id: nil, key: "job_last_success.SlaBreachSweepJob").pick(:value)
    end
    assert recorded.present?, "a sweep that cannot prove it ran is indistinguishable from one that died"
  end
end
