class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :actor       # explicit audit actor (service account, portal contact)
  attribute :request_id, :ip_address, :on_behalf_of

  delegate :user, to: :session, allow_nil: true

  def self.effective_actor
    actor || user
  end

  def self.audit_metadata
    {
      request_id: request_id,
      ip: ip_address,
      on_behalf_of: on_behalf_of
    }.compact.presence
  end
end
