require "test_helper"

class ConnectorsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def create_connector(**overrides)
    Connector.create!({
      name: "CRM", provider: "http_json", target: "contacts",
      config: { "endpoint_url" => "https://api.example.com/c" },
      field_mapping: { "external_id" => "id", "email" => "email" }
    }.merge(overrides))
  end

  # --- Admin UI ---

  test "admin can list, create, view, and run a connector" do
    sign_in_as users(:admin)

    get admin_connectors_path
    assert_response :success

    get new_admin_connector_path(provider: "http_json")
    assert_response :success

    assert_difference "Connector.count", 1 do
      post admin_connectors_path, params: { connector: {
        name: "My CRM", provider: "http_json", target: "contacts", schedule_interval_minutes: 60,
        config: { endpoint_url: "https://api.example.com/contacts" },
        field_mapping: { external_id: "id", email: "email", name: "name" },
        credentials: { api_key: "topsecret" }
      } }
    end
    connector = Connector.order(:id).last
    assert_redirected_to admin_connector_path(connector)
    assert_equal "topsecret", connector.credentials_hash["api_key"]

    get admin_connector_path(connector)
    assert_response :success

    assert_enqueued_with(job: ConnectorSyncJob) do
      post sync_admin_connector_path(connector)
    end
  end

  test "editing without re-entering the api key keeps the stored secret" do
    sign_in_as users(:admin)
    connector = create_connector
    connector.update!(credentials_hash: { "api_key" => "keepme" })

    patch admin_connector_path(connector), params: { connector: {
      name: "Renamed", provider: "http_json", target: "contacts",
      field_mapping: { external_id: "id" }, credentials: { api_key: "" }
    } }
    assert_equal "keepme", connector.reload.credentials_hash["api_key"]
    assert_equal "Renamed", connector.name
  end

  test "pause and resume toggle status" do
    sign_in_as users(:admin)
    connector = create_connector
    post pause_admin_connector_path(connector)
    assert connector.reload.status_paused?
    post resume_admin_connector_path(connector)
    assert connector.reload.status_active?
  end

  test "non-admins cannot reach connectors" do
    sign_in_as users(:supervisor)
    get admin_connectors_path
    assert_response :forbidden
  end

  # --- Webhook ingress ---

  test "a correctly-signed webhook enqueues a sync" do
    connector = create_connector
    body = '{"event":"changed"}'
    sig = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", connector.webhook_secret, body)}"
    assert_enqueued_with(job: ConnectorSyncJob) do
      post connector_webhook_path(connector), params: body,
           headers: { "X-Docket-Signature" => sig, "CONTENT_TYPE" => "application/json" }
    end
    assert_response :accepted
  end

  test "a wrongly-signed webhook is rejected and enqueues nothing" do
    connector = create_connector
    assert_no_enqueued_jobs only: ConnectorSyncJob do
      post connector_webhook_path(connector), params: '{"event":"changed"}',
           headers: { "X-Docket-Signature" => "sha256=deadbeef", "CONTENT_TYPE" => "application/json" }
    end
    assert_response :unauthorized
  end

  test "a webhook to an unknown / paused connector is a 404" do
    paused = create_connector(status: :paused)
    body = "{}"
    sig = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", paused.webhook_secret, body)}"
    post connector_webhook_path(paused), params: body,
         headers: { "X-Docket-Signature" => sig, "CONTENT_TYPE" => "application/json" }
    assert_response :not_found
  end

  # --- Scheduler ---

  test "the scheduler enqueues only due connectors" do
    due = create_connector(schedule_interval_minutes: 30, last_synced_at: 2.hours.ago)
    create_connector(schedule_interval_minutes: 30, last_synced_at: 5.minutes.ago) # not due
    create_connector(schedule_interval_minutes: nil) # manual-only

    assert_enqueued_jobs 1, only: ConnectorSyncJob do
      ConnectorSchedulerJob.perform_now
    end
    assert_enqueued_with(job: ConnectorSyncJob, args: [ due.id, { trigger: "scheduled" } ])
  end
end
