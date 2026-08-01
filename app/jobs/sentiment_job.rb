# Flags sentiment on inbound customer messages (staff assist, §4).
# Stored in message metadata; rendered as a chip in the console.
class SentimentJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return if message.nil?

    client = Llm.client
    return if client.nil?

    prompt = AssistPrompts.sentiment(message)

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
