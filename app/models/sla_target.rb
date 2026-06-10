class SlaTarget < ApplicationRecord
  include Audited

  belongs_to :sla_policy

  # Mirrors Case#priority; asserted equal in tests.
  enum :priority, { low: 0, normal: 1, high: 2, urgent: 3 }, prefix: true

  validates :priority, presence: true, uniqueness: { scope: :sla_policy_id }
  validates :first_response_minutes, :resolution_minutes,
            numericality: { only_integer: true, greater_than: 0 }
end
