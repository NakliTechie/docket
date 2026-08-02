class LiveChatAssistantJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    LiveChatAssistant.new(message).run if message
  end
end
