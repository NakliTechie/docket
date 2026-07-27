require "test_helper"

# R1: an operator at 2am previously had `curl /up` (proves the process booted)
# and `docker logs`. They could not tell whether the queue was draining or
# whether the SLA sweep had run since Tuesday.
class HealthCheckTest < ActionDispatch::IntegrationTest
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

  test "a never-run sweep is not reported as failure" do
    get "/healthz"
    assert_response :success,
                    "a fresh deployment has not had a chance yet; crying wolf on boot trains operators to ignore this"
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
