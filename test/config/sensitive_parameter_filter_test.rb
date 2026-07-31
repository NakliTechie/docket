require "test_helper"

class SensitiveParameterFilterTest < ActiveSupport::TestCase
  test "oauth codes and webhook URLs are filtered without hiding ordinary codes" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      "code" => "oauth-one-time-code",
      "postal_code" => "560001",
      "webhook_endpoint" => { "url" => "https://hooks.example.test/secret" },
      "credentials" => { "webhook_url" => "https://chat.example.test/token" }
    )

    assert_equal "[FILTERED]", filtered["code"]
    assert_equal "560001", filtered["postal_code"]
    assert_equal "[FILTERED]", filtered.dig("webhook_endpoint", "url")
    assert_equal "[FILTERED]", filtered.dig("credentials", "webhook_url")
  end
end
