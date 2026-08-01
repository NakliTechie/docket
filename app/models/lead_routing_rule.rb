# A declarative lead-routing rule (PG1) — the lead-side mirror of RoutingRule.
# Conditions are "any" when blank; a rule matches when ALL its set conditions
# hold. The action assigns an owner by strategy. Rules are evaluated in
# `position` order on lead creation (see LeadRouting); the first matching active
# rule wins. A rule with no conditions is a valid catch-all (place it last).
class LeadRoutingRule < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include HumanEnums
  include TenantReferentialIntegrity

  humanizes_enums :then_assignment

  # How to pick the owner. round_robin / least_loaded draw from the lead-owner
  # pool (active users with lead:write); specific_user names one.
  enum :then_assignment, { round_robin: 0, least_loaded: 1, specific_user: 2 },
       prefix: :assign, default: :round_robin

  belongs_to :then_owner, -> { with_deleted }, class_name: "User", optional: true

  validates :name, presence: true
  validates :if_source, inclusion: { in: Lead.sources.keys }, allow_blank: true
  validates :then_owner_id, presence: true, if: :assign_specific_user?
  validates_same_tenant :then_owner

  normalizes :if_email_domain, with: ->(domain) { domain.to_s.strip.downcase.delete_prefix("@").presence }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  # ALL set conditions must match (blank conditions are "any").
  def matches?(lead)
    return false if if_source.present? && if_source != lead.source
    if if_company_contains.present?
      return false unless lead.company_name.to_s.downcase.include?(if_company_contains.strip.downcase)
    end
    if if_email_domain.present?
      return false unless lead.email.to_s.split("@").last.to_s.downcase == if_email_domain
    end
    true
  end

  # Compact, already-translated summaries for the admin index.
  def conditions_summary
    parts = []
    parts << "#{Lead.human_attribute_name(:source)} = #{I18n.t("leads.enum.source.#{if_source}")}" if if_source.present?
    parts << "#{I18n.t('lead_routing_rules.fields.if_company_contains')} ⊃ “#{if_company_contains}”" if if_company_contains.present?
    parts << "#{I18n.t('lead_routing_rules.fields.if_email_domain')} = @#{if_email_domain}" if if_email_domain.present?
    parts << I18n.t("lead_routing_rules.summary.any") if parts.empty?
    parts
  end

  def action_summary
    return "#{I18n.t('lead_routing_rules.enum.then_assignment.specific_user')}: #{then_owner&.name}" if assign_specific_user?
    I18n.t("lead_routing_rules.enum.then_assignment.#{then_assignment}")
  end
end
