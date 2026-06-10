# Key-value store for admin-managed deployment settings (default queue,
# SLA policy, LLM endpoint, SSO, CORS). Values whose keys look secret
# are redacted in the audit log.
class Setting < ApplicationRecord
  include Audited

  SECRET_KEY_PATTERN = /(_secret|_password|_api_key|_client_secret|_token)\z/

  validates :key, presence: true, uniqueness: true

  def self.get(key, default = nil)
    where(key: key.to_s).pick(:value).then { |v| v.nil? ? default : v }
  end

  def self.set(key, value)
    setting = find_or_initialize_by(key: key.to_s)
    setting.value = value
    setting.save!
    value
  end

  def self.unset(key)
    where(key: key.to_s).find_each(&:destroy)
  end

  def secret?
    key.to_s.match?(SECRET_KEY_PATTERN)
  end

  private

  def audit_redacted_attributes
    secret? ? super | %w[value] : super
  end
end
