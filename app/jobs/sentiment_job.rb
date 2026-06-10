# Flags sentiment on inbound citizen messages (staff assist, §4).
# Stored in message metadata; rendered as a chip in the console.
class SentimentJob < ApplicationJob
  queue_as :default

  def perform(message)
    client = Llm.client
    return if client.nil?

    prompt = <<~PROMPT
      [TASK:sentiment]
      Classify the sentiment of this citizen message as positive, neutral, or negative.
      Message: #{message.body.truncate(2000)}
      Respond with JSON: {"sentiment": ..., "confidence": 0.0-1.0}
    PROMPT

    result = client.chat([ { role: "user", content: prompt } ], json: true)
    sentiment = result["sentiment"].to_s.presence_in(%w[positive neutral negative])
    return unless sentiment

    Current.set(actor: nil) do
      message.update!(metadata: (message.metadata || {}).merge("sentiment" => sentiment))
    end
  rescue Llm::Error
    nil
  end
end
