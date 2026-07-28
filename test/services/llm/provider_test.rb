require "test_helper"

class Llm::ProviderTest < ActiveSupport::TestCase
  # H1: the `fake` backend answers with canned text, not a model. It must never
  # be offered or usable in a real deployment.
  test "fake is selectable in local envs but not in production" do
    assert_includes Llm.selectable_providers, "fake", "dev/test may use the demo backend"

    with_env("production") do
      refute_includes Llm.selectable_providers, "fake", "a real deployment must not offer the demo backend"
      assert_includes Llm.selectable_providers, "in_deployment", "the real providers still show"
    end
  end

  test "the fake provider yields no client outside a local env" do
    Current.set(actor: nil) { Setting.set("llm_provider", "fake") }
    assert_instance_of Llm::FakeClient, Llm.client, "usable in dev/test"

    with_env("production") do
      assert_nil Llm.client, "fake never backs a real deployment — AI stays disabled instead"
    end
  end

  private

  def with_env(name)
    original = Rails.env
    Rails.env = name
    yield
  ensure
    Rails.env = original
  end
end
