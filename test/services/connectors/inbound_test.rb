require "test_helper"

# PG2 — inbound omnichannel. Provider payload parsing + signature/handshake +
# the Connectors::Inbound message→case loop + reply-out dispatch.
class Connectors::InboundTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  FakeRequest = Struct.new(:raw_post, :headers, :query_parameters, keyword_init: true)

  def whatsapp
    Connector.create!(name: "WA", provider: "whatsapp_cloud", status: :active,
                      config: { "phone_number_id" => "PNID" },
                      credentials_hash: { "access_token" => "tok", "app_secret" => "shh" })
  end

  def telegram
    Connector.create!(name: "TG", provider: "telegram_bot", status: :active,
                      config: { "chat_id" => "999" }, credentials_hash: { "bot_token" => "BOT" })
  end

  def wa_payload(body, from: "919876500000", name: "Asha")
    { "entry" => [ { "changes" => [ { "field" => "messages", "value" => {
      "contacts" => [ { "wa_id" => from, "profile" => { "name" => name } } ],
      "messages" => [ { "from" => from, "id" => "wamid.#{body.length}", "type" => "text",
                        "text" => { "body" => body } } ]
    } } ] } ] }
  end

  def tg_payload(body, chat: 4455, name: "Ravi")
    { "update_id" => 7, "message" => { "message_id" => 11,
      "from" => { "id" => chat, "first_name" => name, "username" => "#{name.downcase}_k" },
      "chat" => { "id" => chat, "type" => "private" }, "text" => body } }
  end

  # --- provider parsing -------------------------------------------------------

  test "WhatsApp ingest normalizes a text message and ignores status receipts" do
    provider = whatsapp.provider_instance
    out = provider.ingest(wa_payload("My pension is delayed"))
    assert_equal 1, out.size
    m = out.first
    assert_equal "919876500000", m[:external_thread_id]
    assert_equal "Asha", m.dig(:sender, :name)
    assert_equal "919876500000", m.dig(:sender, :phone)
    assert_equal "whatsapp", m[:channel]
    assert_equal "My pension is delayed", m[:body]

    status_only = { "entry" => [ { "changes" => [ { "value" => {
      "statuses" => [ { "id" => "wamid.1", "status" => "delivered" } ] } } ] } ] }
    assert_empty provider.ingest(status_only)
  end

  test "Telegram ingest normalizes a message and ignores non-message updates" do
    provider = telegram.provider_instance
    out = provider.ingest(tg_payload("Power cut in sector 5"))
    assert_equal 1, out.size
    m = out.first
    assert_equal "4455", m[:external_thread_id]
    assert_equal "Ravi", m.dig(:sender, :name)
    assert_nil m.dig(:sender, :phone)
    assert_equal "telegram", m[:channel]
    assert_empty provider.ingest({ "update_id" => 8, "edited_channel_post" => {} })
  end

  test "WhatsApp signature + GET verification are fail-closed" do
    provider = whatsapp.provider_instance
    raw = JSON.generate(wa_payload("hi"))
    good = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "shh", raw)}"
    assert provider.inbound_authentic?(FakeRequest.new(raw_post: raw, headers: { "X-Hub-Signature-256" => good }))
    refute provider.inbound_authentic?(FakeRequest.new(raw_post: raw, headers: { "X-Hub-Signature-256" => "sha256=nope" }))
    refute provider.inbound_authentic?(FakeRequest.new(raw_post: raw, headers: {}))

    secret = provider.connector.webhook_secret
    assert_equal "C123", provider.verification_challenge(
      "hub.mode" => "subscribe", "hub.verify_token" => secret, "hub.challenge" => "C123")
    assert_nil provider.verification_challenge(
      "hub.mode" => "subscribe", "hub.verify_token" => "wrong", "hub.challenge" => "C123")
  end

  test "Telegram inbound auth compares the secret-token header to webhook_secret" do
    provider = telegram.provider_instance
    secret = provider.connector.webhook_secret
    assert provider.inbound_authentic?(FakeRequest.new(headers: { "X-Telegram-Bot-Api-Secret-Token" => secret }))
    refute provider.inbound_authentic?(FakeRequest.new(headers: { "X-Telegram-Bot-Api-Secret-Token" => "x" }))
    refute provider.inbound_authentic?(FakeRequest.new(headers: {}))
  end

  # --- the message → case loop ------------------------------------------------

  test "process opens a case + contact + inbound message on the provider's channel" do
    wa = whatsapp
    cases = Connectors::Inbound.process(wa, wa_payload("My pension is delayed", from: "9198", name: "Asha"))
    assert_equal 1, cases.size
    kase = cases.first
    assert_equal "whatsapp", kase.channel
    assert_equal wa, kase.source_connector
    assert_equal "9198", kase.source_thread_id
    assert_equal "whatsapp:9198", kase.contact.external_id
    assert_equal "Asha", kase.contact.name
    msg = kase.messages.last
    assert msg.direction_inbound?
    assert_equal kase.contact, msg.author
    assert_equal "My pension is delayed", msg.body
  end

  test "a second message on the same thread threads onto the open case" do
    wa = whatsapp
    first = Connectors::Inbound.process(wa, wa_payload("one", from: "9198")).first
    again = Connectors::Inbound.process(wa, wa_payload("two", from: "9198")).first
    assert_equal first.id, again.id
    assert_equal 2, first.reload.messages.count
    assert_equal 1, Contact.where(external_id: "whatsapp:9198").count
  end

  test "a different sender opens a separate case" do
    wa = whatsapp
    a = Connectors::Inbound.process(wa, wa_payload("a", from: "9198")).first
    b = Connectors::Inbound.process(wa, wa_payload("b", from: "9111")).first
    assert_not_equal a.id, b.id
  end

  # --- reply-out --------------------------------------------------------------

  test "Reply.dispatch maps each channel to its provider send action" do
    wa = whatsapp
    wcase = Case.create!(subject: "x", channel: :whatsapp, contact: contacts(:asha),
                         source_connector: wa, source_thread_id: "9198")
    wmsg = wcase.messages.new(kind: :public_reply, direction: :outbound, body: "On it")
    action, args = Connectors::Reply.dispatch(wcase, wmsg)
    assert_equal "send_text_message", action
    assert_equal({ "to" => "9198", "text" => "On it" }, args)

    tg = telegram
    tcase = Case.create!(subject: "y", channel: :telegram, contact: contacts(:asha),
                         source_connector: tg, source_thread_id: "4455")
    tmsg = tcase.messages.new(kind: :public_reply, direction: :outbound, body: "Looking")
    taction, targs = Connectors::Reply.dispatch(tcase, tmsg)
    assert_equal "send_message", taction
    assert_equal({ "chat_id" => "4455", "text" => "Looking" }, targs)
  end

  test "Reply.deliver sends through the provider and stamps the result" do
    wa = whatsapp
    kase = Case.create!(subject: "x", channel: :whatsapp, contact: contacts(:asha),
                        source_connector: wa, source_thread_id: "9198")
    msg = kase.messages.create!(kind: :public_reply, direction: :outbound,
                                author: users(:agent_a), body: "On it!")
    fake = Object.new
    def fake.calls = @calls ||= []
    def fake.invoke(action, args)
      calls << [ action, args ]
      { "message_id" => "wamid.out" }
    end
    wa.define_singleton_method(:provider_instance) { fake }
    Connectors::Reply.deliver(msg)

    assert_equal [ "send_text_message", { "to" => "9198", "text" => "On it!" } ], fake.calls.first
    assert_equal true, msg.reload.metadata.dig("delivery", "ok")
    assert_equal "wamid.out", msg.metadata.dig("delivery", "message_id")
  end

  test "an outbound reply on a messaging case enqueues delivery and skips email" do
    wa = whatsapp
    kase = Case.create!(subject: "x", channel: :whatsapp, contact: contacts(:asha),
                        source_connector: wa, source_thread_id: "9198")
    assert_enqueued_with(job: ConnectorReplyJob) do
      assert_no_enqueued_emails do
        kase.messages.create!(kind: :public_reply, direction: :outbound,
                              author: users(:agent_a), body: "hi")
      end
    end
  end
end
