require "test_helper"

class LiveChatAssistantTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:result, :prompts) do
    def chat(messages, json: false)
      prompts << messages.first[:content]
      result
    end
  end

  setup do
    @contact = Contact.create!(name: "Chat Customer", email: "bot-chat@example.com")
    @case = Case.create!(subject: "Refund", contact: @contact, channel: :live_chat)
    @chat, = LiveChat.issue!(kase: @case, contact: @contact)
    @message = @case.messages.create!(kind: :public_reply, direction: :inbound,
                                      author: @contact, body: "When will my refund arrive?")
  end

  test "publishes a high-confidence answer grounded in public articles" do
    article = ReferenceDoc.create!(title: "Refund timing", body: "Refunds arrive within five business days.",
                                   visibility: :public, status: :published, locale: "en")
    client = FakeClient.new({ "answer" => "Refunds arrive within five business days.",
                              "confidence" => 0.91, "fully_grounded" => true }, [])

    assert_difference "@case.messages.where(kind: :agent_turn).count", 1 do
      LiveChatAssistant.new(@message, client: client).run
    end

    reply = @case.messages.order(:id).last
    assert_equal [ article.id ], reply.metadata["article_ids"]
    assert_equal @message.id, reply.metadata["source_message_id"]
    assert_includes client.prompts.first, "Refunds arrive within five business days."
  end

  test "one inbound message receives at most one bot response" do
    ReferenceDoc.create!(title: "Refund timing", body: "Refunds arrive within five business days.",
                         visibility: :public, status: :published, locale: "en")
    client = FakeClient.new({ "answer" => "Five business days.", "confidence" => 0.91,
                              "fully_grounded" => true }, [])

    LiveChatAssistant.new(@message, client: client).run
    assert_no_difference "@case.messages.where(kind: :agent_turn).count" do
      LiveChatAssistant.new(@message.reload, client: client).run
    end
  end

  test "never sends an internal article to the public bot prompt" do
    ReferenceDoc.create!(title: "Public refund answer", body: "Use the public process for a refund.",
                         visibility: :public, status: :published, locale: "en")
    ReferenceDoc.create!(title: "Internal escalation", body: "SECRET INTERNAL ROUTING CODE",
                         visibility: :internal, status: :published, locale: "en")
    client = FakeClient.new({ "answer" => "Use the public process.", "confidence" => 0.9,
                              "fully_grounded" => true }, [])

    LiveChatAssistant.new(@message, client: client).run

    assert_includes client.prompts.first, "Use the public process for a refund."
    assert_not_includes client.prompts.first, "SECRET INTERNAL ROUTING CODE"
  end

  test "does not publish ungrounded or low-confidence output" do
    ReferenceDoc.create!(title: "Refund timing", body: "Refund timing details.",
                         visibility: :public, status: :published, locale: "en")
    client = FakeClient.new({ "answer" => "Maybe tomorrow", "confidence" => 0.4,
                              "fully_grounded" => false }, [])

    assert_no_difference "@case.messages.where(kind: :agent_turn).count" do
      LiveChatAssistant.new(@message, client: client).run
    end
  end

  test "knowledge entitlement disables public bot retrieval" do
    ReferenceDoc.create!(title: "Refund timing", body: "Refund timing details.",
                         visibility: :public, status: :published, locale: "en")
    tenants(:primary).set_feature!("service_desk.kb", false)
    client = FakeClient.new({ "answer" => "Answer", "confidence" => 0.9,
                              "fully_grounded" => true }, [])

    assert_no_difference "@case.messages.where(kind: :agent_turn).count" do
      LiveChatAssistant.new(@message, client: client).run
    end
    assert_empty client.prompts
  end
end
