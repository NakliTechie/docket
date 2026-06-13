# A declarative case-routing rule (see CaseRouting). Conditions are "any" when
# blank; a rule matches when ALL its set conditions hold. Actions set the
# queue/category/priority and pick an assignee by strategy. Evaluated in
# `position` order; the first matching active rule wins.
class RoutingRule < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :match_category, class_name: "Category", optional: true
  belongs_to :then_queue, class_name: "CaseQueue", optional: true
  belongs_to :then_category, class_name: "Category", optional: true
  belongs_to :then_assignee, class_name: "User", optional: true

  # How to pick the assignee from the (then_queue or the case's) queue.
  enum :then_assignment, { keep: 0, round_robin: 1, least_loaded: 2, specific_user: 3 },
       prefix: :assign, default: :keep

  validates :name, presence: true
  validates :if_channel, inclusion: { in: Case.channels.keys }, allow_blank: true
  validates :if_priority, inclusion: { in: Case.priorities.keys }, allow_blank: true
  validates :then_priority, inclusion: { in: Case.priorities.keys }, allow_blank: true
  validates :then_assignee_id, presence: true, if: :assign_specific_user?
  validate :has_a_condition
  validate :has_an_action

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  # ALL set conditions must match (blank conditions are "any").
  def matches?(kase)
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

  def has_a_condition
    return if [ if_channel, if_priority, match_category_id, if_subject_contains ].any?(&:present?)
    errors.add(:base, :needs_condition)
  end

  def has_an_action
    return if then_queue_id.present? || then_category_id.present? || then_priority.present? || !assign_keep?
    errors.add(:base, :needs_action)
  end
end
