# Shared prompt builders for the HTML and REST assist surfaces. Every string
# derived from a case, customer, or knowledge document is fenced as untrusted
# data before it reaches the model.
module AssistPrompts
  MAX_SUMMARY_MESSAGES = 60
  MAX_SUMMARY_CHARS = 16_000

  module_function

  def sentiment(message)
    <<~PROMPT
      [TASK:sentiment]
      Classify the sentiment of this customer message as positive, neutral, or negative.
      #{Llm.fence_instruction}
      Customer message:
      #{Llm.fence(message.body.to_s.truncate(2000))}
      Respond with JSON: {"sentiment": ..., "confidence": 0.0-1.0}
    PROMPT
  end

  def summarise(kase)
    thread = kase.messages.order(:created_at).last(MAX_SUMMARY_MESSAGES).map { |message|
      "#{message.author_display_name} (#{message.kind}): #{message.body.truncate(800)}"
    }.join("\n").truncate(MAX_SUMMARY_CHARS)

    <<~PROMPT
      [TASK:summarise]
      Summarise this case thread for a staff member in 3 sentences or fewer, ending with the next required action.
      #{Llm.fence_instruction}
      Subject:
      #{Llm.fence(kase.subject)}
      Original request:
      #{Llm.fence(kase.description.presence || "(none)")}
      Thread:
      #{Llm.fence(thread.presence || "(no messages yet)")}
    PROMPT
  end

  def suggest_reply(kase, grounding:)
    first_inbound = kase.messages.where(direction: :inbound).order(:created_at).first
    last_inbound = kase.messages.where(direction: :inbound).order(:created_at).last
    grounding_text = grounding.map { |item| "- #{item.title}: #{item.text.truncate(600)}" }.join("\n")

    <<~PROMPT
      [TASK:suggest]
      Draft a reply for a staff member to send to the customer. Be concrete, polite, and grounded ONLY in the context provided. Do not invent case facts.
      #{Llm.fence_instruction}
      Subject:
      #{Llm.fence(kase.subject)}
      Original request:
      #{Llm.fence(kase.description.presence || first_inbound&.body || "")}
      Latest customer message:
      #{Llm.fence(last_inbound&.body&.truncate(1500) || "(none)")}
      Grounding:
      #{Llm.fence(grounding_text.presence || "(none)")}
      Reply with the message text only.
    PROMPT
  end
end
