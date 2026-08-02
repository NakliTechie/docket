class LiveChatAssistant
  MIN_CONFIDENCE = 0.7

  def initialize(message, client: Llm.client)
    @message = message
    @client = client
  end

  def run
    return unless @client && @message.case.live_chat&.active?
    tenant = Tenant.find(@message.tenant_id)
    return unless tenant.feature?("service_desk.portal") && tenant.feature?("service_desk.kb")
    return if answered?

    articles = Retrieval.search_articles(@message.body, scope: ReferenceDoc.public_kb, limit: 3)
    return if articles.empty?

    prompt = <<~PROMPT
      [TASK:public_live_chat]
      Answer the customer's question using only the published knowledge-base excerpts below.
      If the excerpts do not contain the answer, set fully_grounded to false.
      Do not request passwords, OTPs, payment credentials, or government identity numbers.
      Tell the customer that a support person can continue the conversation.
      #{Llm.fence_instruction}

      Customer message:
      #{Llm.fence(@message.body)}

      Published excerpts:
      #{articles.map { |article| "- #{article.title}: #{article.body.truncate(2000)}" }.join("\n")}

      Respond with JSON: {"answer": ..., "confidence": 0.0-1.0, "fully_grounded": true/false}
    PROMPT
    result = @client.chat([ { role: "user", content: prompt } ], json: true)
    return unless result.is_a?(Hash)
    return unless result["fully_grounded"] == true
    return if result["confidence"].to_f < MIN_CONFIDENCE || result["answer"].blank?

    Current.set(actor: nil) do
      @message.case.messages.create!(
        kind: :agent_turn, direction: :outbound, author: nil, body: result["answer"],
        source_message: @message,
        metadata: {
          "ai" => "live_chat", "source_message_id" => @message.id,
          "confidence" => result["confidence"], "article_ids" => articles.map(&:id)
        }
      )
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  rescue Llm::Error => error
    Rails.logger.warn("live chat assistant failed for message #{@message.id}: #{error.class}")
  end

  private

  def answered?
    @message.assistant_response.present?
  end
end
