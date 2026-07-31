class RoutingRuleExecution < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :routing_rule, optional: true
  belongs_to :case, -> { with_deleted }

  validates :rule_name, :case_status_changed_at, :scheduled_for, :executed_at, presence: true
  validates :case_status_changed_at,
            uniqueness: { scope: %i[tenant_id routing_rule_id case_id] }, if: :routing_rule_id?
  validates_same_tenant :routing_rule, :case
end
