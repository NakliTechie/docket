require "test_helper"

# The sample-data loader populates every surface for each scenario, so demos /
# guides / walkthroughs never hit an empty state.
class DemoSeedTest < ActiveSupport::TestCase
  def seed(scenario)
    ENV["DOCKET_SEED_SCENARIO"] = scenario
    load Rails.root.join("db/seeds/demo.rb").to_s
  ensure
    ENV.delete("DOCKET_SEED_SCENARIO")
  end

  test "the saas scenario seeds a private-first brand and every surface" do
    seed("saas")

    assert_equal "Acme Cloud", Setting.get("brand_name")
    assert_operator Case.count, :>=, 30
    assert_operator Lead.count, :>=, 3
    assert ServiceAccount.exists?(name: "Support effector agent")
    assert SharedCredential.exists?(name: "support_api")
    assert Connector.exists?(provider: "http_json")
    assert_operator ConnectorInvocation.status_proposed.count, :>=, 2
    assert Sequence.exists?(name: "New-lead welcome")
    {
      super_admin: "arjun@docket.local",
      client_admin: "sunita@docket.local",
      finance: "farah@docket.local",
      sales: "sanjay@docket.local",
      customer_service: "priya@docket.local",
      technical: "tarun@docket.local",
      readonly: "meena@docket.local"
    }.each do |role, email|
      assert User.exists?(email_address: email, role: role),
        "demo seed has no #{role} login"
    end

    %w[new triaged in_progress waiting_on_customer resolved closed reopened].each do |status|
      assert Case.where(status: status).exists?, "expected at least one #{status} case"
    end
  end

  test "scenarios set their own brand and queues" do
    seed("retail")
    assert_equal "ShopNova", Setting.get("brand_name")
    assert CaseQueue.exists?(name: "Returns & Refunds")
  end

  test "the gov scenario remains available as a vertical" do
    seed("gov")
    assert_equal "Public Grievance Portal", Setting.get("brand_name")
    assert CaseQueue.exists?(name: "Pensions")
  end

  # C8: fictional demo data must never land in a real deployment. The loader
  # aborts unless the environment is local or DOCKET_ALLOW_DEMO_SEED=1 is set.
  test "refuses to seed outside a local environment without an explicit opt-in" do
    had_flag = ENV.delete("DOCKET_ALLOW_DEMO_SEED")
    original_env = Rails.env

    Rails.env = "production"
    error = assert_raises(SystemExit) do
      capture_io { load Rails.root.join("db/seeds/demo.rb").to_s }
    end

    refute error.success?, "aborted with a non-zero status, before any write"
    refute Setting.get("demo_seeded"), "no seeding happened"
  ensure
    Rails.env = original_env
    ENV["DOCKET_ALLOW_DEMO_SEED"] = had_flag if had_flag
  end

  test "the documented compose demo explicitly passes the production seed gate" do
    entrypoint = Rails.root.join("bin/docker-entrypoint").read

    assert_includes entrypoint,
      "DOCKET_ALLOW_DEMO_SEED=1 ./bin/rails db:seed demo:seed"
  end

  test "is idempotent when a fresh process has no tenant context" do
    previous_test_tenant = ActsAsTenant.test_tenant
    ActsAsTenant.test_tenant = nil
    ActsAsTenant.current_tenant = nil

    seed("saas")
    counts_after_first_seed = [ Case.count, Message.count, Project.count, WorkItem.count ]

    # Container restarts begin without request or test tenant context.
    ActsAsTenant.current_tenant = nil
    seed("saas")

    assert_equal counts_after_first_seed,
      [ Case.count, Message.count, Project.count, WorkItem.count ]
  ensure
    ActsAsTenant.current_tenant = nil
    ActsAsTenant.test_tenant = previous_test_tenant
  end
end
