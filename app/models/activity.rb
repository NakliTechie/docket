# PG2 — a logged interaction or a planned task hung off any CRM/desk record.
# The foundational "activity" object Salesforce/HubSpot centre their rep UX on:
# it feeds the Customer-360 timeline and the rep task queue. Polymorphic subject
# (Contact/Lead/Deal/Case). All kinds start open; a task/call/meeting typically
# carries a due date and is worked to done, a note is usually just recorded.
class Activity < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include HumanEnums
  include TenantReferentialIntegrity

  humanizes_enums :kind, :status

  SUBJECT_TYPES = %w[Contact Lead Deal Case].freeze

  enum :kind, { call: 0, email: 1, meeting: 2, note: 3, task: 4 }, default: :task, prefix: :kind
  enum :status, { open: 0, done: 1, canceled: 2 }, default: :open, prefix: :status

  belongs_to :subject, polymorphic: true
  belongs_to :owner, -> { with_deleted }, class_name: "User", optional: true

  validates :title, presence: true
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }
  validates_same_tenant :owner
  # subject is polymorphic (the reflection helper doesn't apply); guard it like
  # WorkLink does — a cross-tenant subject would leak that record's identity.
  validate :subject_is_same_tenant

  scope :open_activities, -> { status_open }
  scope :scheduled, -> { where.not(due_at: nil) }
  scope :overdue, -> { status_open.where.not(due_at: nil).where("due_at < ?", Time.current) }
  scope :for_owner, ->(user) { where(owner_id: user) }
  scope :recent_first, -> { order(Arel.sql("due_at IS NULL"), :due_at, created_at: :desc) }

  def overdue? = status_open? && due_at.present? && due_at.past?

  def display_label = "#{human_kind}: #{title}"

  def complete!
    update!(status: :done, completed_at: Time.current)
  end

  private

  def subject_is_same_tenant
    return if subject_id.blank? || subject_type.blank?
    return unless SUBJECT_TYPES.include?(subject_type)

    owner_tenant = ActsAsTenant.without_tenant do
      subject_type.constantize.unscoped.where(id: subject_id).pick(:tenant_id)
    end
    errors.add(:subject, :cross_tenant) if owner_tenant.present? && owner_tenant != tenant_id
  end
end
