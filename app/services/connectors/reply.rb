module Connectors
  # Routes an outbound case reply back out through the messaging connector that
  # originated the case (PG2) — closing the loop WhatsApp/Telegram opened on
  # intake. A human (or the AI agent) already authored the reply, so this is a
  # direct, pre-authorized invocation: it never parks for approval, but still
  # applies connector state, budgets, idempotency, actor attribution, and the
  # durable ConnectorInvocation audit trail. The provider message id (or any
  # error) is also stamped on message metadata for the case timeline.
  module Reply
    module_function

    def deliver(message)
      kase = message.case
      connector = kase.source_connector
      return unless connector&.ingests?

      action, args = dispatch(kase, message)
      return unless action

      invocation = Connectors::Invoke.call_direct(
        connector, action, args: args, principal: message.author,
        on_behalf_of: "case:#{kase.id}", reasoning: "authorized case reply",
        idempotency_key: "case-message:#{message.id}:reply"
      )
      if invocation.status_succeeded?
        result = invocation.result || {}
        stamp(message, "ok" => true, "message_id" => result["message_id"],
                       "via" => connector.provider, "invocation_id" => invocation.id)
      elsif invocation.status_failed? && !connector.operational?
        stamp(message, "ok" => false, "skipped" => true, "reason" => "connector_inactive",
                       "status" => connector.status, "invocation_id" => invocation.id)
      elsif invocation.status_failed?
        stamp(message, "ok" => false, "error" => invocation.error,
                       "invocation_id" => invocation.id)
      end
    rescue Connectors::Error => e
      stamp(message, "ok" => false, "error" => e.message)
    end

    # → [action_key, args] for the case's channel, or nil to skip.
    def dispatch(kase, message)
      case kase.channel
      when "whatsapp"
        to = kase.source_thread_id.presence || kase.contact.phone
        return nil if to.blank?
        [ "send_text_message", { "to" => to, "text" => message.outbound_body } ]
      when "telegram"
        return nil if kase.source_thread_id.blank?
        [ "send_message", { "chat_id" => kase.source_thread_id, "text" => message.outbound_body } ]
      end
    end

    # update_columns: json column, no validations/audit churn, no callback recursion.
    def stamp(message, delivery)
      message.update_columns(metadata: (message.metadata || {}).merge("delivery" => delivery))
    end
  end
end
