require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "probability settings fail validation outside the unit interval" do
    assert_raises(ActiveRecord::RecordInvalid) { Setting.set("ai_route_confidence", 1.1) }
    assert_raises(ActiveRecord::RecordInvalid) { Setting.set("ai_resolve_confidence", -0.1) }
  end

  test "the shared contract rejects polluted shapes and clamps probabilities" do
    assert SettingContract.invalid?(SettingContract.coerce("ai_route_confidence", { bad: true }))
    assert_equal 0.0, SettingContract.coerce("ai_route_confidence", -5)
    assert_equal 1.0, SettingContract.coerce("ai_resolve_confidence", "5")
    assert SettingContract.invalid?(SettingContract.coerce("llm_endpoint_url", "not a url"))
    assert_equal "https://models.example.test/v1", SettingContract.coerce(
      "llm_endpoint_url", "https://models.example.test/v1"
    )
    assert_equal "inbound.example.test", SettingContract.coerce(
      "sequence_reply_domain", "inbound.example.test"
    )
    assert SettingContract.invalid?(SettingContract.coerce("sequence_reply_domain", "bad domain"))
  end
end
