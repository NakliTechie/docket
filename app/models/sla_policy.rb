# First-response + resolution targets per priority (handoff §2).
# Targets live in SlaTarget rows, one per priority.
class SlaPolicy < ApplicationRecord
  include SoftDeletable
  include Audited

  has_many :sla_targets, dependent: :destroy
  has_many :cases, dependent: nil

  accepts_nested_attributes_for :sla_targets, allow_destroy: true

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }

  def self.default
    find_by(id: Setting.get("default_sla_policy_id"))
  end

  def target_for(priority)
    sla_targets.detect { |t| t.priority == priority.to_s }
  end
end
