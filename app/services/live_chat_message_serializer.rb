module LiveChatMessageSerializer
  module_function

  def call(message)
    {
      id: message.id,
      body: message.body,
      direction: message.direction,
      created_at: message.created_at.iso8601
    }
  end
end
