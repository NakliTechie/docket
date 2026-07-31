# A declarative case-routing rule (see CaseRouting). Conditions are "any" when
# blank; a rule matches when ALL its set conditions hold. Actions set the
# queue/category/priority and pick an assignee by strategy. Evaluated in
# `position` order; the first matching active rule wins.
class RoutingRule < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :match_category, class_name: "Category", optional: true
  belongs_to :then_queue, class_name: "CaseQueue", optional: true
  belongs_to :then_category, class_name: "Category", optional: true
  belongs_to :then_assignee, class_name: "User", optional: true
  has_many :routing_rule_executions, dependent: :nullify
  has_many :routed_cases, class_name: "Case", foreign_key: :routed_by_rule_id,
                          dependent: :nullify, inverse_of: :routed_by_rule

  enum :trigger_type, { case_created: "case_created", elapsed_time: "elapsed_time" },
       prefix: :trigger, default: :case_created

  # How to pick the assignee from the (then_queue or the case's) queue.
  enum :then_assignment, { keep: 0, round_robin: 1, least_loaded: 2, specific_user: 3 },
       prefix: :assign, default: :keep

  validates :name, presence: true
  validates :if_channel, inclusion: { in: Case.channels.keys }, allow_blank: true
  validates :if_priority, inclusion: { in: Case.priorities.keys }, allow_blank: true
  validates :then_priority, inclusion: { in: Case.priorities.keys }, allow_blank: true
  validates :if_status, inclusion: { in: Case.statuses.keys }, allow_blank: true
  validates :after_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 525_600 },
                            presence: true, if: :trigger_elapsed_time?
  validates :then_assignee_id, presence: true, if: :assign_specific_user?
  validates_same_tenant :match_category, :then_queue, :then_category, :then_assignee
  validate :trigger_configuration
  validate :has_a_condition
  validate :has_an_action

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }
  scope :intake, -> { where(trigger_type: "case_created") }
  scope :scheduled, -> { where(trigger_type: "elapsed_time") }

  # ALL set conditions must match (blank conditions are "any").
  def matches?(kase)
    return false if if_status.present? && if_status != kase.status
    return false if if_channel.present? && if_channel != kase.channel
    return false if if_priority.present? && if_priority != kase.priority
    return false if match_category_id.present? && match_category_id != kase.category_id
    if if_subject_contains.present?
      haystack = "#{kase.subject} #{kase.description}".downcase
      return false unless haystack.include?(if_subject_contains.strip.downcase)
    end
    true
  end

  # Compact, already-translated summaries for the admin index.
  def conditions_summary
    parts = []
    if trigger_elapsed_time?
      clock = use_business_hours? ? I18n.t("routing_rules.summary.business_minutes") : I18n.t("routing_rules.summary.minutes")
      parts << I18n.t("routing_rules.summary.elapsed", count: after_minutes,
                      status: I18n.t("cases.enum.status.#{if_status}"), clock: clock)
    end
    parts << "#{Case.human_attribute_name(:channel)} = #{I18n.t("cases.enum.channel.#{if_channel}")}" if if_channel.present?
    parts << "#{Case.human_attribute_name(:priority)} = #{I18n.t("cases.enum.priority.#{if_priority}")}" if if_priority.present?
    parts << "#{Category.model_name.human}: #{match_category.name}" if match_category
    parts << "#{I18n.t('routing_rules.fields.if_subject_contains')} ⊃ “#{if_subject_contains}”" if if_subject_contains.present?
    parts
  end

  def actions_summary
    parts = []
    parts << "→ #{then_queue.name}" if then_queue
    parts << "#{Category.model_name.human}: #{then_category.name}" if then_category
    parts << "#{Case.human_attribute_name(:priority)}: #{I18n.t("cases.enum.priority.#{then_priority}")}" if then_priority.present?
    parts << I18n.t("routing_rules.enum.then_assignment.#{then_assignment}") unless assign_keep?
    parts
  end

  private

  def trigger_configuration
    if trigger_elapsed_time?
      errors.add(:if_status, :blank) if if_status.blank?
    elsif after_minutes.present? || if_status.present?
      errors.add(:base, :intake_has_schedule)
    end
  end

  def has_a_condition
    return if [ if_status, if_channel, if_priority, match_category_id, if_subject_contains ].any?(&:present?)
    errors.add(:base, :needs_condition)
  end

  def has_an_action
    return if then_queue_id.present? || then_category_id.present? || then_priority.present? || !assign_keep?
    errors.add(:base, :needs_action)
  end
end
