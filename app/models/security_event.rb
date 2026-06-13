# Append-only security trail for auth events that have no user to attach
# to (failed/throttled logins). Deliberately separate from the
# hash-chained AuditEntry so the case-audit chain stays clean while the
# operator still gets a queryable failed-login record.
class SecurityEvent < ApplicationRecord
  KINDS = %w[login_failed login_throttled sso_rejected].freeze

  # Denormalized filter column only (like AuditEntry): NOT acts_as_tenant, so a
  # logging write never raises from the auth path even when no tenant resolves.
  belongs_to :tenant, optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :recent_first, -> { order(id: :desc) }

  # Per-tenant read view (H1): super_admin / isolated see everything; otherwise
  # scope to the current tenant so one tenant's failed-login emails/IPs aren't
  # visible to another.
  def self.visible_to(user)
    return all if Tenant.isolated_deployment? || !!user&.role_super_admin?
    where(tenant_id: ActsAsTenant.current_tenant&.id)
  end

  # Never raise from the auth path — a logging failure must not break login.
  def self.record(kind, email: nil, ip_address: nil, user_agent: nil, metadata: nil)
    create!(kind: kind, email: email.to_s.strip.downcase.presence,
            ip_address: ip_address, user_agent: user_agent.to_s.presence,
            metadata: metadata.presence, tenant_id: ActsAsTenant.current_tenant&.id,
            created_at: Time.current)
  rescue StandardError => e
    Rails.logger.warn("SecurityEvent.record failed: #{e.class}: #{e.message}")
    nil
  end

  def readonly?
    persisted?
  end
end
