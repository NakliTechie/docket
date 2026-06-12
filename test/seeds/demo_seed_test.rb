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

    %w[new triaged in_progress waiting_on_citizen resolved closed reopened].each do |status|
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
end
