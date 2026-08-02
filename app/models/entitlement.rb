class Entitlement < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  belongs_to :organisation, -> { with_deleted }, optional: true
  belongs_to :contact, -> { with_deleted }, optional: true
  belongs_to :sla_policy, -> { with_deleted }

  validates :name, presence: true,
                   uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validates :starts_at, presence: true
  validate :exactly_one_holder
  validate :coverage_window_is_ordered

  scope :covering, ->(at) {
    where("starts_at <= ? AND (ends_at IS NULL OR ends_at > ?)", at, at)
  }
  scope :usable, -> { joins(:sla_policy).where(sla_policies: { deleted_at: nil }) }

  def self.policy_for(contact, at: Time.current)
    return if contact.nil?

    direct = usable.covering(at).where(contact_id: contact.id).order(starts_at: :desc, id: :desc).first
    return direct.sla_policy if direct
    return if contact.organisation_id.blank?

    usable.covering(at).where(organisation_id: contact.organisation_id)
      .order(starts_at: :desc, id: :desc).first&.sla_policy
  end

  def holder
    contact || organisation
  end

  def holder_label
    contact ? contact.name : organisation&.name
  end

  private

  def exactly_one_holder
    return if contact_id.present? ^ organisation_id.present?

    errors.add(:base, :exactly_one_entitlement_holder)
  end

  def coverage_window_is_ordered
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, :after_start)
  end
end
