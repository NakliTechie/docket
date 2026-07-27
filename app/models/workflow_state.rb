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
  validates :wip_limit, numericality: { greater_than: 0 }, allow_nil: true

  scope :ordered, -> { order(:position) }

  def display_label = name

  def terminal? = category_done?

  # SOFT limit (KanZen's semantics): over-limit is flagged, never blocked. A
  # hard block just teaches people to work around the board.
  def over_wip_limit?(count)
    wip_limit.present? && count > wip_limit
  end
end
