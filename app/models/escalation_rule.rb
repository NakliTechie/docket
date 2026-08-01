# PG3 — an SLA-driven escalation rule. Matches open cases (optionally filtered
# by status/priority) and fires ordered EscalationLevels at increasing delays
# after a reference time:
#   sla_breach  — reference = the breached SLA's due time (needs the breach flag)
#   elapsed_time — reference = when the case entered `if_status`
# Evaluated in position order by CaseEscalation. Composes existing primitives —
# no new sweep plumbing beyond an idempotency ledger.
class EscalationRule < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include HumanEnums
  include TenantReferentialIntegrity

  humanizes_enums :trigger_type

  enum :trigger_type, { sla_breach: 0, elapsed_time: 1 }, prefix: :trigger, default: :sla_breach

  BREACH_CLOCKS = %w[resolution first_response].freeze

  # Levels fire in delay order — order by after_minutes, not a manual position.
  has_many :escalation_levels, -> { order(:after_minutes, :id) }, dependent: :destroy
  accepts_nested_attributes_for :escalation_levels, allow_destroy: true,
                                reject_if: ->(attrs) { attrs["after_minutes"].blank? }

  validates :name, presence: true
  validates :breach_clock, inclusion: { in: BREACH_CLOCKS }, if: :trigger_sla_breach?
  validates :if_status, inclusion: { in: Case.statuses.keys }, allow_blank: true
  validates :if_priority, inclusion: { in: Case.priorities.keys }, allow_blank: true
  validates :if_status, presence: true, if: :trigger_elapsed_time?

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  # Cases this rule currently applies to (tenant-scoped via acts_as_tenant).
  def matching_cases
    scope = Case.open_cases
    scope = scope.where(priority: if_priority) if if_priority.present?
    if trigger_sla_breach?
      scope.where(breach_flag => true)
    else
      scope.where(status: if_status).where.not(status_changed_at: nil)
    end
  end

  def matches?(kase)
    return false unless kase.open?
    return false if if_priority.present? && kase.priority != if_priority
    if trigger_sla_breach?
      kase.public_send(breach_flag)
    else
      kase.status == if_status && kase.status_changed_at.present?
    end
  end

  # The moment the escalation clock starts for this case.
  def reference_at(kase)
    trigger_sla_breach? ? kase.public_send(breach_due_at) : kase.status_changed_at
  end

  def conditions_summary
    parts = []
    parts << (trigger_sla_breach? ? I18n.t("escalation_rules.summary.on_breach", clock: breach_clock.tr("_", " ")) : I18n.t("escalation_rules.summary.in_status", status: I18n.t("cases.enum.status.#{if_status}")))
    parts << "#{Case.human_attribute_name(:priority)} = #{I18n.t("cases.enum.priority.#{if_priority}")}" if if_priority.present?
    parts
  end

  private

  def breach_flag = "#{breach_clock}_breached"
  def breach_due_at = "#{breach_clock}_due_at"
end
