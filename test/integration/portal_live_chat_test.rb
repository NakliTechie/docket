require "test_helper"

class PortalLiveChatTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "anonymous customer starts a live chat backed by a case" do
    assert_difference [ "LiveChat.count", "Case.count", "Message.count" ], 1 do
      post portal_live_chat_path, params: { live_chat_submission: {
        name: "Meera", email: "meera.chat@example.com", message: "My refund is delayed"
      } }
    end

    chat = LiveChat.order(:id).last
    assert_redirected_to portal_live_chat_path
    assert_equal "live_chat", chat.case.channel
    assert_equal "My refund is delayed", chat.case.messages.first.body
    assert_equal chat.contact, chat.case.contact

    follow_redirect!
    assert_response :success
    assert_select "[data-controller=live-chat]"
    assert_match "My refund is delayed", response.body
  end

  test "customer appends a message and keeps the chat alive" do
    start_chat
    chat = LiveChat.order(:id).last
    original_expiry = chat.expires_at
    travel 1.minute

    assert_difference "chat.case.messages.count", 1 do
      post message_portal_live_chat_path, params: { body: "Here is the receipt number" }, as: :json
    end

    assert_response :created
    assert_equal "Here is the receipt number", response.parsed_body["body"]
    assert_operator chat.reload.expires_at, :>, original_expiry
    assert_equal chat.contact, chat.case.messages.order(:id).last.author
  end

  test "ending a chat revokes message access" do
    start_chat
    chat = LiveChat.order(:id).last

    delete end_chat_portal_live_chat_path
    assert_redirected_to new_portal_live_chat_path
    assert chat.reload.ended_at

    post message_portal_live_chat_path, params: { body: "late" }, as: :json
    assert_redirected_to new_portal_live_chat_path
    assert_equal 1, chat.case.messages.count
  end

  test "anonymous chat cannot attach to an externally verified contact by email" do
    verified = Contact.create!(name: "Verified", email: "verified.chat@example.com", external_id: "oidc:customer-1")

    assert_difference "Contact.count", 1 do
      post portal_live_chat_path, params: { live_chat_submission: {
        name: "Imposter", email: verified.email, message: "Hello"
      } }
    end

    assert_not_equal verified, LiveChat.order(:id).last.contact
    assert_nil LiveChat.order(:id).last.contact.external_id
  end

  test "name and a reachable contact method are required" do
    assert_no_difference "LiveChat.count" do
      post portal_live_chat_path, params: { live_chat_submission: { name: "", message: "Hello" } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "bot is off by default" do
    assert_no_enqueued_jobs only: LiveChatAssistantJob do
      start_chat
    end
  end

  private

  def start_chat
    post portal_live_chat_path, params: { live_chat_submission: {
      name: "Meera", phone: "+919876500000", message: "Please help"
    } }
  end
end
