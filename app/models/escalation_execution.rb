# Idempotency ledger for CaseEscalation (PG3), mirroring RoutingRuleExecution:
# one row per (level, case, reference episode), so overlapping sweeps never
# double-fire a level.
class EscalationExecution < ApplicationRecord
  acts_as_tenant(:tenant)
  include TenantReferentialIntegrity

  belongs_to :escalation_level
  belongs_to :case, class_name: "Case"

  validates :reference_at, :executed_at, presence: true
  validates_same_tenant :escalation_level, :case
end
