# Delivers an outbound case reply back out through its messaging connector
# (PG2), off the request thread. Tenant is auto-propagated by acts_as_tenant.
class ConnectorReplyJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = Message.find_by(id: message_id)
    return unless message

    Connectors::Reply.deliver(message)
  end
end
