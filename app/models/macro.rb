# Admin-managed canned responses with variable interpolation
# (handoff §7). Inserted into the composer client-side; the message
# saved is a plain Message — no special casing downstream.
class Macro < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include TenantReferentialIntegrity

  VARIABLES = %w[contact_name tracking_id agent_name queue_name].freeze

  validates :name, presence: true, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validates :body, presence: true
  belongs_to :set_queue, -> { with_deleted }, class_name: "CaseQueue", optional: true
  belongs_to :set_assignee, -> { with_deleted }, class_name: "User", optional: true

  validates :message_kind, inclusion: { in: %w[public_reply internal_note] }, allow_blank: true
  validates :set_status, inclusion: { in: Case.statuses.keys }, allow_blank: true
  validates :set_priority, inclusion: { in: Case.priorities.keys }, allow_blank: true
  validates_same_tenant :set_queue, :set_assignee
  validate :assignee_is_active

  def render_for(kase, agent: nil)
    body.gsub(/\{\{\s*(\w+)\s*\}\}/) do
      case Regexp.last_match(1)
      when "contact_name" then kase.contact&.name
      when "tracking_id"  then kase.tracking_id
      when "agent_name"   then agent&.name
      when "queue_name"   then kase.queue&.name
      else Regexp.last_match(0)
      end.to_s
    end
  end

  def apply_to!(kase, requested_by:)
    attributes = {}
    attributes[:priority] = set_priority if set_priority.present?
    attributes[:queue] = set_queue if set_queue_id.present?
    attributes[:assignee] = set_assignee if set_assignee_id.present?
    kase.update!(attributes) if attributes.any?
    return true if set_status.blank? || kase.status == set_status

    kase.guarded_transition_to(set_status, requested_by: requested_by)
  end

  def actions_summary
    { message_kind: message_kind, status: set_status, priority: set_priority,
      queue_id: set_queue_id, assignee_id: set_assignee_id }.compact_blank
  end

  private

  def assignee_is_active
    errors.add(:set_assignee, :inactive) if set_assignee && !set_assignee.active?
  end
end
