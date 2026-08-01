require "test_helper"

# PG2 — the inbound webhook endpoint end to end: signature/secret verification,
# the WhatsApp GET handshake, and case creation. Tenant is resolved per request
# (primary in isolated) and the connector is found tenant-scoped.
class ConnectorsInboundTest < ActionDispatch::IntegrationTest
  def whatsapp
    Connector.create!(name: "WA", provider: "whatsapp_cloud", status: :active,
                      config: { "phone_number_id" => "PNID" },
                      credentials_hash: { "access_token" => "tok", "app_secret" => "shh" })
  end

  def telegram
    Connector.create!(name: "TG", provider: "telegram_bot", status: :active,
                      config: { "chat_id" => "999" }, credentials_hash: { "bot_token" => "BOT" })
  end

  def wa_body(text, from: "919876500000")
    JSON.generate({ "entry" => [ { "changes" => [ { "field" => "messages", "value" => {
      "contacts" => [ { "wa_id" => from, "profile" => { "name" => "Asha" } } ],
      "messages" => [ { "from" => from, "id" => "wamid.1", "type" => "text",
                        "text" => { "body" => text } } ] } } ] } ] })
  end

  def signed(secret, body)
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"
  end

  test "a correctly signed WhatsApp webhook opens a case with an inbound message" do
    wa = whatsapp
    body = wa_body("ATM ate my card")
    assert_difference "Case.count", 1 do
      post connector_webhook_path(wa), params: body,
           headers: { "X-Hub-Signature-256" => signed("shh", body), "CONTENT_TYPE" => "application/json" }
    end
    assert_response :ok
    kase = Case.order(:id).last
    assert_equal "whatsapp", kase.channel
    assert_equal wa, kase.source_connector
    assert_equal "ATM ate my card", kase.messages.last.body
  end

  test "a bad WhatsApp signature is rejected and creates nothing" do
    wa = whatsapp
    body = wa_body("spoofed")
    assert_no_difference "Case.count" do
      post connector_webhook_path(wa), params: body,
           headers: { "X-Hub-Signature-256" => "sha256=forged", "CONTENT_TYPE" => "application/json" }
    end
    assert_response :unauthorized
  end

  test "a signed malformed inbound message is rejected without losing it as accepted" do
    wa = whatsapp
    body = '{"entry":'

    assert_no_difference "Case.count" do
      post connector_webhook_path(wa), params: body,
           headers: { "X-Hub-Signature-256" => signed("shh", body), "CONTENT_TYPE" => "text/plain" }
    end

    assert_response :bad_request
  end

  test "the WhatsApp GET handshake echoes the challenge only on a matching verify token" do
    wa = whatsapp
    get connector_webhook_verify_path(wa), params: {
      "hub.mode" => "subscribe", "hub.verify_token" => wa.webhook_secret, "hub.challenge" => "C0DE"
    }
    assert_response :ok
    assert_equal "C0DE", response.body

    get connector_webhook_verify_path(wa), params: {
      "hub.mode" => "subscribe", "hub.verify_token" => "wrong", "hub.challenge" => "C0DE"
    }
    assert_response :forbidden
  end

  test "a Telegram webhook with the right secret-token header opens a case" do
    tg = telegram
    body = JSON.generate({ "update_id" => 1, "message" => { "message_id" => 5,
      "from" => { "id" => 4455, "first_name" => "Ravi" },
      "chat" => { "id" => 4455, "type" => "private" }, "text" => "Power cut" } })
    assert_difference "Case.count", 1 do
      post connector_webhook_path(tg), params: body,
           headers: { "X-Telegram-Bot-Api-Secret-Token" => tg.webhook_secret, "CONTENT_TYPE" => "application/json" }
    end
    assert_response :ok
    assert_equal "telegram", Case.order(:id).last.channel
  end

  test "a non-ingesting connector still triggers a sync, not inbound" do
    effector = Connector.create!(name: "JSON", provider: "http_json", target: "contacts",
                                 config: { "endpoint_url" => "https://api.example.com/c" },
                                 field_mapping: { "external_id" => "id", "email" => "email" })
    body = "{}"
    assert_no_difference "Case.count" do
      post connector_webhook_path(effector), params: body,
           headers: { "X-Docket-Signature" => signed(effector.webhook_secret, body), "CONTENT_TYPE" => "application/json" }
    end
    assert_response :accepted
  end

  # --- PG4: SMS inbound (form-encoded Twilio; the signature IS the auth) ---

  def twilio
    Connector.create!(name: "SMS", provider: "twilio_sms", status: :active,
                      config: { "account_sid" => "AC1", "from" => "+15550000000" },
                      credentials_hash: { "auth_token" => "AUTHTOK" })
  end

  def twilio_signature(token, url, params)
    data = url + params.sort.map { |key, value| "#{key}#{value}" }.join
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA1", token, data))
  end

  test "a correctly signed Twilio SMS webhook (form-encoded) opens a case on the sms channel" do
    sms = twilio
    params = { "From" => "+15551112222", "Body" => "meter reading dispute", "MessageSid" => "SM9" }
    url = connector_webhook_url(sms, host: "www.example.com")
    assert_difference "Case.count", 1 do
      post connector_webhook_path(sms), params: params,
           headers: { "X-Twilio-Signature" => twilio_signature("AUTHTOK", url, params) }
    end
    assert_response :ok
    kase = Case.order(:id).last
    assert_equal "sms", kase.channel
    assert_equal sms, kase.source_connector
    assert_equal "meter reading dispute", kase.messages.last.body
  end

  test "a bad Twilio signature is rejected and creates nothing" do
    sms = twilio
    assert_no_difference "Case.count" do
      post connector_webhook_path(sms), params: { "From" => "+1", "Body" => "spoof", "MessageSid" => "SMX" },
           headers: { "X-Twilio-Signature" => "forged" }
    end
    assert_response :unauthorized
  end
end
