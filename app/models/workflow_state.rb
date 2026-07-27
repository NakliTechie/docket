# A column on a project's board. Per-project, because "In review" is not a
# universal step. `category` is the reporting axis (todo / in_progress / done)
# and is what "is this finished?" asks — never the state's name.
class WorkflowState < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include HumanEnums

  humanizes_enums :category

  enum :category, { todo: 0, in_progress: 1, done: 2 }, default: :todo, prefix: true

  belongs_to :project

  has_many :work_items, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: { scope: :project_id, case_sensitive: false }

  scope :ordered, -> { order(:position) }

  def display_label = name

  def terminal? = category_done?
end
