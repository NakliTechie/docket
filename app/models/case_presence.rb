class CasePresence < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  STALE_AFTER = 2.minutes

  belongs_to :case
  belongs_to :user

  validates :last_seen_at, presence: true
  validates :user_id, uniqueness: { scope: %i[tenant_id case_id] }
  validates_same_tenant :case, :user

  scope :active, -> { where(last_seen_at: STALE_AFTER.ago..) }

  def self.touch_for!(kase, user)
    presence = find_or_create_by!(case: kase, user: user) { |record| record.last_seen_at = Time.current }
    presence.update_columns(last_seen_at: Time.current, updated_at: Time.current) unless presence.previously_new_record?
    where(case: kase).where(last_seen_at: ...STALE_AFTER.ago).delete_all
    presence
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
