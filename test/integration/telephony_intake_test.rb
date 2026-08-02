require "test_helper"

class TelephonyIntakeTest < ActionDispatch::IntegrationTest
  def connector(name: "IVR")
    Connector.create!(name: name, provider: "telephony_webhook", target: "contacts",
                      status: :active, config: {}, field_mapping: {})
  end

  test "signed call webhook creates a phone case and recording reference" do
    ivr = connector
    payload = {
      provider_call_id: "call-100", from_number: "+919876500001", to_number: "18001234",
      status: "completed", duration_seconds: 82,
      recording_url: "https://voice.example.test/recordings/call-100",
      ivr_answers: { language: "hi", topic: "pension" }, transcript: "My pension is delayed.",
      started_at: "2026-08-02T10:00:00Z", ended_at: "2026-08-02T10:01:22Z"
    }

    assert_difference [ "CallRecord.count", "Case.count", "Contact.count", "Message.count" ], 1 do
      post_webhook(ivr, payload)
    end

    assert_response :ok
    call = CallRecord.order(:id).last
    assert_equal "phone", call.case.channel
    assert_equal ivr, call.case.source_connector
    assert_equal "call-100", call.case.source_thread_id
    assert_equal "https://voice.example.test/recordings/call-100", call.recording_url
    assert_equal 82, call.duration_seconds
    assert_equal "My pension is delayed.", call.case.messages.first.body
    assert_equal "phone:+919876500001", call.contact.external_id
  end

  test "replayed call updates the record without duplicating the case or message" do
    ivr = connector
    post_webhook(ivr, { provider_call_id: "call-101", from_number: "+919876500002", status: "ringing" })

    assert_no_difference [ "CallRecord.count", "Case.count", "Message.count" ] do
      post_webhook(ivr, { provider_call_id: "call-101", from_number: "+919876500002",
                          status: "completed", duration_seconds: 10,
                          recording_url: "https://voice.example.test/r/call-101" })
    end

    call = CallRecord.find_by!(provider_call_id: "call-101")
    assert_equal "completed", call.status
    assert_equal 10, call.duration_seconds
  end

  test "terminal call does not regress when callbacks arrive out of order" do
    ivr = connector
    post_webhook(ivr, { provider_call_id: "call-102", from_number: "+919876500003", status: "completed" })
    post_webhook(ivr, { provider_call_id: "call-102", from_number: "+919876500003", status: "ringing" })
    assert_equal "completed", CallRecord.find_by!(provider_call_id: "call-102").status
  end

  test "invalid signature is rejected without creating intake records" do
    ivr = connector
    assert_no_difference [ "CallRecord.count", "Case.count" ] do
      post connector_webhook_path(ivr), params: { provider_call_id: "forged", from_number: "+911" }.to_json,
           headers: { "Content-Type" => "application/json", "X-Docket-Signature" => "sha256=wrong" }
    end
    assert_response :unauthorized
  end

  test "same provider call id remains distinct across connectors" do
    first = connector(name: "PBX A")
    second = connector(name: "PBX B")
    payload = { provider_call_id: "shared-call", from_number: "+919876500004" }

    assert_difference "CallRecord.count", 2 do
      post_webhook(first, payload)
      post_webhook(second, payload)
    end
  end

  private

  def post_webhook(connector, payload)
    raw = payload.to_json
    signature = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", connector.webhook_secret, raw)}"
    post connector_webhook_path(connector), params: raw,
         headers: { "Content-Type" => "application/json", "X-Docket-Signature" => signature }
  end
end
