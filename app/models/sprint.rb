# A time-boxed slice of a project's work. Behaviour (planning moves, close-out,
# velocity) lands in WM3; this is the model WM1 needs so work items can carry a
# sprint from day one.
class Sprint < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include HumanEnums

  humanizes_enums :status

  enum :status, { planned: 0, active: 1, closed: 2 }, default: :planned, prefix: true

  belongs_to :project

  # NOT dependent: :nullify — SoftDeletable#destroy runs destroy callbacks, so
  # nullify would permanently strip sprint_id from every item and a restore
  # could not recover it (taking the sprint's velocity history with it). A
  # soft-deleted sprint simply stops being visible; its items keep the pointer.
  has_many :work_items, dependent: nil
  has_many :audit_entries, as: :auditable, dependent: nil

  validates :name, presence: true
  validate :ends_after_start
  validate :one_active_sprint_per_project

  scope :ordered, -> { order(Arel.sql("starts_on IS NULL"), :starts_on, :id) }

  def display_label = "#{project&.key} #{name}"

  private

  def ends_after_start
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, :before_start)
  end

  def one_active_sprint_per_project
    return unless status_active? && project_id

    clash = Sprint.where(project_id: project_id, status: :active).where.not(id: id).exists?
    errors.add(:status, :another_sprint_active) if clash
  end
end
