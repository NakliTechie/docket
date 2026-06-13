# Key-value store for admin-managed deployment settings (default queue,
# SLA policy, LLM endpoint, SSO, CORS). Values whose keys look secret
# are redacted in the audit log.
class Setting < ApplicationRecord
  include Audited

  SECRET_KEY_PATTERN = /(_secret|_password|_api_key|_client_secret|_token)\z/

  validates :key, presence: true, uniqueness: { scope: :tenant_id }

  # Settings resolve per tenant with a deploy-wide fallback: the current tenant's
  # own row wins, else the global (tenant_id NULL) value. With no tenant in scope
  # (the platform console / without_tenant), only the global value is seen.
  # Writes go to the current tenant (or global when none is set). Setting is NOT
  # acts_as_tenant — this nullable-fallback is the deliberate exception.
  def self.get(key, default = nil)
    k = key.to_s
    tid = ActsAsTenant.current_tenant&.id
    value = where(tenant_id: tid, key: k).pick(:value)
    value = where(tenant_id: nil, key: k).pick(:value) if value.nil? && tid
    value.nil? ? default : value
  end

  def self.set(key, value)
    setting = find_or_initialize_by(tenant_id: ActsAsTenant.current_tenant&.id, key: key.to_s)
    setting.value = value
    setting.save!
    value
  end

  def self.unset(key)
    where(tenant_id: ActsAsTenant.current_tenant&.id, key: key.to_s).find_each(&:destroy)
  end

  def secret?
    key.to_s.match?(SECRET_KEY_PATTERN)
  end

  private

  def audit_redacted_attributes
    secret? ? super | %w[value] : super
  end
end
