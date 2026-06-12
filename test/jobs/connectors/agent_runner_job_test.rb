require "test_helper"

class Connectors::AgentRunnerJobTest < ActiveJob::TestCase
  def kase
    cases(:pension_case)
  end

  def agent
    ServiceAccount.create!(name: "Case agent", scopes: %w[connectors:invoke], active: true)
  end

  def connector
    Connector.create!(name: "Records API", provider: "http_json", target: "contacts",
      config: { "action_url" => "https://api.example.com/do" },
      field_mapping: { "external_id" => "id" }, enabled_actions: %w[post_json])
  end

  test "run_later enqueues the job with case + agent ids" do
    a = agent
    assert_enqueued_with(job: Connectors::AgentRunnerJob, args: [ kase.id, a.id ]) do
      Connectors::AgentRunner.run_later(kase, agent: a)
    end
  end

  test "perform runs the loop when the LLM is enabled" do
    Setting.set("llm_provider", "fake")
    connector
    assert_difference("ConnectorInvocation.count", 1) do
      Connectors::AgentRunnerJob.perform_now(kase.id, agent.id)
    end
  end

  test "perform is a safe no-op for a missing case or agent" do
    assert_nothing_raised { Connectors::AgentRunnerJob.perform_now(-1, -1) }
  end
end
