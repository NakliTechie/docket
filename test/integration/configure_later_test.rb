require "test_helper"

# Configure-later lifecycle: a connector is wired as a draft (excluded from
# agents + the scheduler) and goes live only once its required credentials are
# present — "wire DigiLocker now, licence later".
class ConfigureLaterTest < ActionDispatch::IntegrationTest
  test "a form-created connector starts as a draft" do
    sign_in_as users(:admin)
    post admin_connectors_path, params: { connector: {
      name: "DigiLocker", provider: "http_json", target: "contacts",
      field_mapping: { external_id: "id" }, config: { endpoint_url: "https://api.example.com/c" }
    } }
    assert Connector.order(:id).last.status_draft?
  end

  test "configured? reflects whether the required secrets are present" do
    assert Connector.new(provider: "http_json").configured? # optional bearer token

    slack = Connector.create!(name: "S", provider: "slack_webhook")
    assert_not slack.configured?
    slack.credentials_hash = { "webhook_url" => "https://hooks.slack.com/services/x" }
    slack.save!
    assert slack.configured?
  end

  test "a shared credential can satisfy the requirement" do
    sc = SharedCredential.new(name: "slack", label: "Slack")
    sc.secrets_hash = { "webhook_url" => "https://hooks.slack.com/services/y" }
    sc.save!
    slack = Connector.create!(name: "S", provider: "slack_webhook", status: :draft, shared_credential: sc)
    assert slack.configured?
  end

  test "activating a configured draft takes it live; an unconfigured one is blocked" do
    sign_in_as users(:admin)
    slack = Connector.create!(name: "S", provider: "slack_webhook", status: :draft)

    post activate_admin_connector_path(slack)
    assert slack.reload.status_draft? # blocked — no webhook_url yet
    assert flash[:alert].present?

    slack.credentials_hash = { "webhook_url" => "https://hooks.slack.com/services/x" }
    slack.save!
    post activate_admin_connector_path(slack)
    assert slack.reload.status_active?
  end

  test "a draft connector is invisible to the agent (excluded from its tools)" do
    agent = ServiceAccount.create!(name: "A", scopes: %w[connectors:invoke], active: true)
    draft = Connector.create!(name: "S", provider: "slack_webhook", status: :draft,
                              enabled_actions: %w[post_message])
    draft.credentials_hash = { "webhook_url" => "https://hooks.slack.com/services/x" }
    draft.save!

    assert_no_difference "ConnectorInvocation.count" do
      Connectors::AgentRunner.new(cases(:pension_case), agent: agent, client: Llm::FakeClient.new).run
    end
  end
end
