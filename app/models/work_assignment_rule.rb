class WorkAssignmentRule < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity

  belongs_to :project
  belongs_to :assignee, -> { with_deleted }, class_name: "User"

  validates :work_kind, inclusion: { in: WorkItem.kinds.keys },
                        uniqueness: { scope: %i[tenant_id project_id] }
  validate :assignee_is_active
  validates_same_tenant :project, :assignee

  def display_label = "#{project&.key} #{work_kind} → #{assignee&.name}"

  private

  def assignee_is_active
    errors.add(:assignee, :inactive) unless assignee&.active?
  end
end
