class ProjectTemplateItem < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited
  include TenantReferentialIntegrity
  include HumanEnums

  humanizes_enums :kind, :priority

  enum :kind, WorkItem.kinds, default: :task, prefix: true
  enum :priority, WorkItem.priorities, default: :normal, prefix: true

  belongs_to :project_template, inverse_of: :project_template_items

  validates :title, presence: true
  validates :estimate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :due_offset_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                              allow_nil: true
  validates_same_tenant :project_template
end
