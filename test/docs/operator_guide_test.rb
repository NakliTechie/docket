require "test_helper"

class OperatorGuideTest < ActiveSupport::TestCase
  setup do
    @guide = Rails.root.join("docs/OPERATOR-GUIDE.md").read
    @handoff = Rails.root.join("docs/DEPLOYMENT-HANDOFF.md").read
    @go_live_path = Rails.root.join("docs/GO-LIVE-VALIDATION.md")
  end

  test "documents the live connector count" do
    count = Connectors::Registry.keys.size

    assert_includes @guide, "**#{count}** provider implementations"
    assert_includes @handoff, "The #{count} connectors"
  end

  test "documents every functional role and service-account scope" do
    Authz::ROLE_PERMISSIONS.each_key do |role|
      assert_includes @guide, "`#{role}`"
    end
    ServiceAccount::SCOPES.each do |scope|
      assert_includes @guide, "`#{scope}`"
    end
  end

  test "documents every tenant feature key" do
    Features::KEYS.each do |feature|
      label = feature.split(".").last
      assert_match(/`[^`]*#{Regexp.escape(label)}[^`]*`/, @guide, feature)
    end
  end

  test "documents the sovereign BI topology and extension boundary" do
    normalized_guide = @guide.gsub(/\s+/, " ")

    [
      "read replica of the primary database",
      "cache, queue, or cable databases",
      "default_transaction_read_only",
      "A dashboard filter is not an authorization boundary",
      "X-API-Key",
      "no proprietary extension marketplace",
      "AGPL forkability",
      "self-hosted n8n connector"
    ].each do |expectation|
      assert_includes normalized_guide, expectation
    end

    assert_includes @handoff, "Optional BI"
    assert_includes @handoff, "database-enforced tenant isolation"
  end

  test "go-live evidence guide is linked and covers every external launch gate" do
    assert @go_live_path.exist?
    assert_includes @handoff, "[GO-LIVE-VALIDATION.md](GO-LIVE-VALIDATION.md)"

    guide = @go_live_path.read
    [ "Host, TLS, and health", "Outbound mail and authentication", "Inbound mail",
      "Migration rehearsal", "Launch connector certification",
      "Production model qualification", "Human accessibility pass" ].each do |heading|
      assert_includes guide, heading
    end
  end
end
