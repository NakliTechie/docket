class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :actor       # explicit audit actor (service account, portal contact)
  attribute :tenant      # the resolved tenant (always set; the singleton in isolated mode)
  attribute :request_id, :ip_address, :on_behalf_of, :delegation_id

  delegate :user, to: :session, allow_nil: true

  def self.effective_actor
    actor || user
  end

  def self.audit_metadata
    {
      request_id: request_id,
      ip: ip_address,
      on_behalf_of: on_behalf_of,
      delegation_id: delegation_id
    }.compact.presence
  end
end
