require "test_helper"

class LiveChatChannelTest < ActionCable::Channel::TestCase
  setup do
    stub_connection current_tenant: tenants(:primary), current_user: nil
    kase = Case.create!(subject: "Cable chat", contact: contacts(:asha), channel: :live_chat)
    @chat, @raw_token = LiveChat.issue!(kase: kase, contact: kase.contact)
  end

  test "valid bearer token subscribes only to its chat stream" do
    subscribe token: @raw_token

    assert subscription.confirmed?
    assert_has_stream_for @chat
  end

  test "unknown bearer token is rejected" do
    subscribe token: "wrong-token"

    assert subscription.rejected?
  end

  test "portal entitlement disables existing chat streams" do
    tenants(:primary).set_feature!("service_desk.portal", false)

    subscribe token: @raw_token

    assert subscription.rejected?
  end
end
