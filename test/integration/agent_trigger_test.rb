require "test_helper"

# Wiring the dispatch loop to the app: a staffer hands a case to the
# designated AI effector agent from the case page.
class AgentTriggerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def kase
    cases(:pension_case)
  end

  def designate_agent
    sa = ServiceAccount.create!(name: "Case agent", scopes: %w[connectors:invoke], active: true)
    Setting.set("llm_provider", "fake")     # AI layer on (FakeClient)
    Setting.set("effector_agent_id", sa.id) # an agent designated
    sa
  end

  test "running the agent on a case enqueues the dispatch job for the designated agent" do
    sa = designate_agent
    sign_in_as users(:admin)
    assert_enqueued_with(job: Connectors::AgentRunnerJob, args: [ kase.id, sa.id ]) do
      post run_agent_case_path(kase)
    end
    assert_redirected_to case_path(kase)
    assert_match sa.name, flash[:notice].to_s
  end

  test "running the agent with none configured alerts and enqueues nothing" do
    Setting.set("llm_provider", "fake") # enabled, but no agent designated
    sign_in_as users(:admin)
    assert_no_enqueued_jobs { post run_agent_case_path(kase) }
    assert_redirected_to case_path(kase)
    assert flash[:alert].present?
  end

  test "a readonly user cannot run the agent" do
    designate_agent
    sign_in_as users(:readonly)
    post run_agent_case_path(kase)
    assert_response :forbidden
  end

  test "the Run AI agent button shows only when an agent is available" do
    sign_in_as users(:admin)

    get case_path(kase)
    assert_response :success
    assert_no_match "Run AI agent", response.body # nothing configured yet

    designate_agent
    get case_path(kase)
    assert_match "Run AI agent", response.body
  end

  test "an admin designates the effector agent through settings" do
    sa = ServiceAccount.create!(name: "Triage", scopes: %w[connectors:invoke], active: true)
    sign_in_as users(:admin)
    patch admin_settings_path, params: { effector_agent_id: sa.id.to_s }
    assert_equal sa.id, Setting.get("effector_agent_id")
  end
end
