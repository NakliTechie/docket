module Connectors
  # Routes an outbound case reply back out through the messaging connector that
  # originated the case (PG2) — closing the loop WhatsApp/Telegram opened on
  # intake. A human (or the AI agent) already authored the reply, so this is a
  # direct provider send, not an agent-gated effector invocation. The provider
  # message id (or any error) is recorded on the message metadata for audit.
  module Reply
    module_function

    def deliver(message)
      kase = message.case
      connector = kase.source_connector
      return unless connector&.ingests?

      action, args = dispatch(kase, message)
      return unless action

      result = connector.provider_instance.invoke(action, args)
      stamp(message, "ok" => true, "message_id" => result["message_id"], "via" => connector.provider)
    rescue Connectors::Error => e
      stamp(message, "ok" => false, "error" => e.message)
    end

    # → [action_key, args] for the case's channel, or nil to skip.
    def dispatch(kase, message)
      case kase.channel
      when "whatsapp"
        to = kase.source_thread_id.presence || kase.contact.phone
        return nil if to.blank?
        [ "send_text_message", { "to" => to, "text" => message.body } ]
      when "telegram"
        return nil if kase.source_thread_id.blank?
        [ "send_message", { "chat_id" => kase.source_thread_id, "text" => message.body } ]
      end
    end

    # update_columns: json column, no validations/audit churn, no callback recursion.
    def stamp(message, delivery)
      message.update_columns(metadata: (message.metadata || {}).merge("delivery" => delivery))
    end
  end
end
