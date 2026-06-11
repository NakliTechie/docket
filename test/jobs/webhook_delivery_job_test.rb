require "test_helper"

class WebhookDeliveryJobTest < ActiveJob::TestCase
  setup do
    @endpoint = WebhookEndpoint.create!(name: "Receiver", url: "https://receiver.example.in/hook",
                                        events: WebhookEndpoint::EVENTS)
  end

  test "case lifecycle publishes signed deliveries" do
    assert_difference "WebhookDelivery.count", 1 do
      Case.create!(subject: "Hooked", contact: contacts(:asha))
    end
    delivery = WebhookDelivery.order(:id).last
    assert_equal "case.created", delivery.event
    assert_equal "Hooked", delivery.payload["data"]["subject"]
  end

  test "delivery posts hmac-signed payload and records success" do
    received = {}
    stub_request(:post, "https://receiver.example.in/hook").to_return do |request|
      received[:body] = request.body
      received[:signature] = request.headers["X-Docket-Signature"]
      received[:event] = request.headers["X-Docket-Event"]
      { status: 200 }
    end

    delivery = @endpoint.webhook_deliveries.create!(event: "case.created", payload: { "data" => { "id" => 1 } })
    WebhookDeliveryJob.perform_now(delivery)

    expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", @endpoint.secret, received[:body])}"
    assert_equal expected, received[:signature]
    assert_equal "case.created", received[:event]
    assert delivery.reload.status_delivered?
    assert_equal 200, delivery.response_code
    assert delivery.delivered_at.present?
  end

  test "forged signatures cannot be produced without the secret" do
    stub_request(:post, "https://receiver.example.in/hook").to_return(status: 200)
    delivery = @endpoint.webhook_deliveries.create!(event: "case.created", payload: { "data" => {} })
    WebhookDeliveryJob.perform_now(delivery)

    body = JSON.generate(delivery.payload)
    wrong = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "other-secret", body)}"
    refute_equal wrong, @endpoint.sign(body)
  end

  test "5xx responses retry and record the attempt" do
    stub_request(:post, "https://receiver.example.in/hook").to_return(status: 503)
    delivery = @endpoint.webhook_deliveries.create!(event: "case.created", payload: { "data" => {} })

    assert_enqueued_with(job: WebhookDeliveryJob) do
      WebhookDeliveryJob.perform_now(delivery)
    rescue WebhookDeliveryJob::DeliveryError
      # perform_now re-raises after scheduling the retry
    end
    assert delivery.reload.status_pending?
    assert_equal 503, delivery.response_code
    assert_equal 1, delivery.attempts
  end

  test "connection errors retry too" do
    stub_request(:post, "https://receiver.example.in/hook").to_raise(Errno::ECONNREFUSED)
    delivery = @endpoint.webhook_deliveries.create!(event: "case.created", payload: { "data" => {} })
    assert_enqueued_with(job: WebhookDeliveryJob) do
      WebhookDeliveryJob.perform_now(delivery)
    rescue WebhookDeliveryJob::DeliveryError
      # retry_on re-raises once attempts are exhausted in-line
    end
    assert delivery.reload.status_pending?
    assert delivery.last_error.present?
  end

  test "delivery to a loopback/metadata host is failed without connecting (M22 SSRF)" do
    # Bypass validation to simulate an endpoint that became internal.
    @endpoint.update_column(:url, "http://169.254.169.254/latest/meta-data")
    delivery = @endpoint.webhook_deliveries.create!(event: "case.created", payload: { "data" => {} })

    # No WebMock stub: if the job tried to connect, net-connect is disabled
    # and it would raise — so reaching "failed/blocked" proves no request.
    WebhookDeliveryJob.perform_now(delivery)
    assert_equal "failed", delivery.reload.status
    assert_match(/blocked/, delivery.last_error)
  end

  test "internal notes never publish webhooks" do
    assert_no_difference "WebhookDelivery.count" do
      Message.create!(case: cases(:pension_case), kind: :internal_note,
                      direction: :outbound, author: users(:agent_a), body: "Secret note")
    end
  end

  test "inactive endpoints receive nothing" do
    @endpoint.update!(active: false)
    assert_no_difference "WebhookDelivery.count" do
      Case.create!(subject: "Silent", contact: contacts(:asha))
    end
  end

  test "status change and resolve publish distinct events" do
    kase = Case.create!(subject: "Lifecycle", contact: contacts(:asha))
    kase.transition_to!(:triaged)
    kase.transition_to!(:in_progress)
    kase.transition_to!(:resolved)
    events = WebhookDelivery.where("payload LIKE ?", "%Lifecycle%").pluck(:event)
    assert_includes events, "case.created"
    assert_includes events, "case.status_changed"
    assert_includes events, "case.resolved"
  end
end
