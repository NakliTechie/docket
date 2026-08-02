require "test_helper"

class RealtimeIntakeTest < ActiveSupport::TestCase
  test "live chat tokens are stored as digests and expire closed" do
    kase = Case.create!(subject: "Chat", contact: contacts(:asha), channel: :live_chat)
    chat, raw_token = LiveChat.issue!(kase: kase, contact: kase.contact)

    assert_not_equal raw_token, chat.token_digest
    assert_equal chat, LiveChat.authenticate(raw_token)
    chat.update!(expires_at: 1.second.ago)
    assert_nil LiveChat.authenticate(raw_token)
  end

  test "recording reference accepts http urls without credentials" do
    connector = Connector.create!(name: "IVR", provider: "telephony_webhook", target: "contacts",
                                  status: :active, config: {}, field_mapping: {})
    kase = Case.create!(subject: "Call", contact: contacts(:asha), channel: :phone)
    call = CallRecord.new(case: kase, contact: kase.contact, connector: connector,
                          provider_call_id: "c-1", from_number: "+9198")

    call.recording_url = "https://voice.example.test/c-1"
    assert call.valid?
    call.recording_url = "https://user:password@voice.example.test/c-1"
    assert_not call.valid?
    call.recording_url = "javascript:alert(1)"
    assert_not call.valid?
  end

  test "assistant source message must belong to the same case" do
    first = Case.create!(subject: "First", contact: contacts(:asha), channel: :live_chat)
    second = Case.create!(subject: "Second", contact: contacts(:asha), channel: :live_chat)
    source = first.messages.create!(body: "Question", direction: :inbound, author: contacts(:asha))
    response = second.messages.new(body: "Answer", kind: :agent_turn, source_message: source)

    assert_not response.valid?
    assert response.errors[:source_message].present?
  end
end
