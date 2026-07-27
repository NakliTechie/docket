# The unit of work in the Work module — deliberately "work item", not "issue" or
# "ticket": a ticket is a Case (a customer asking for something) and conflating
# the two is how service desks and trackers turn into the same broken table.
#
# Identity is KEY-123 (project key + per-project number), minted on create.
class WorkItem < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include Labelable
  include HumanEnums

  humanizes_enums :kind, :priority

  enum :kind, { task: 0, story: 1, bug: 2, epic: 3 }, default: :task, prefix: true
  # Same vocabulary as Case#priority so one person reading both surfaces isn't
  # translating between two scales.
  enum :priority, { low: 0, normal: 1, high: 2, urgent: 3 }, default: :normal, prefix: true

  belongs_to :project
  belongs_to :workflow_state, -> { with_deleted }
  belongs_to :assignee, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :reporter, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :parent, -> { with_deleted }, class_name: "WorkItem", optional: true
  belongs_to :sprint, -> { with_deleted }, optional: true

  has_many :children, class_name: "WorkItem", foreign_key: :parent_id, dependent: :nullify,
           inverse_of: :parent
  has_many :work_comments, -> { order(:created_at) }, dependent: :destroy
  has_many :work_links, dependent: :destroy
  has_many :work_watches, dependent: :destroy
  has_many :watchers, through: :work_watches, source: :user
  has_many :audit_entries, as: :auditable, dependent: nil
  has_many :approval_requests, as: :subject, dependent: :destroy

  validates :title, presence: true
  validates :estimate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :parent_is_not_self_or_descendant
  validate :state_belongs_to_project
  validate :sprint_belongs_to_project

  before_validation :assign_number, on: :create
  before_save :stamp_closed_at, if: :workflow_state_id_changed?
  after_update_commit :echo_state_to_linked_cases, if: :saved_change_to_workflow_state_id?

  scope :open, -> { joins(:workflow_state).where.not(workflow_states: { category: :done }) }
  scope :closed, -> { joins(:workflow_state).where(workflow_states: { category: :done }) }
  scope :assigned_to, ->(user) { where(assignee: user) }

  def reference = "#{project.key}-#{number}"

  def display_label = "#{reference} #{title}"

  def done? = workflow_state&.category_done?

  # The single transition point, so every move is audited and closed_at stays
  # honest — mirrors Case#transition_to! rather than inventing a second idiom.
  def transition_to!(state)
    update!(workflow_state: state)
  end

  private

  def assign_number
    self.number ||= project&.next_item_number!
    self.workflow_state ||= project&.default_state
  end

  def stamp_closed_at
    self.closed_at = done? ? Time.current : nil
  end

  # An agent watching a case should not have to open the tracker to learn the
  # engineering work finished. Internal note only — the customer never asked
  # for a work item and should not be told about one.
  def echo_state_to_linked_cases
    work_links.where(linkable_type: "Case").includes(:linkable).find_each do |link|
      kase = link.linkable
      next if kase.nil?

      kase.messages.create!(
        body: I18n.t("work.escalation.state_echo",
                     reference: reference, state: workflow_state.name),
        kind: :internal_note,
        author: nil
      )
    end
  end

  def parent_is_not_self_or_descendant
    return if parent_id.blank?

    if parent_id == id
      errors.add(:parent, :cannot_be_self)
      return
    end

    seen = [ id ].compact
    node = parent
    while node
      if seen.include?(node.id)
        errors.add(:parent, :cycle)
        return
      end
      seen << node.id
      node = node.parent
    end
  end

  def state_belongs_to_project
    return if workflow_state.blank? || project_id.blank?
    return if workflow_state.project_id == project_id

    errors.add(:workflow_state, :not_in_project)
  end

  def sprint_belongs_to_project
    return if sprint.blank? || project_id.blank?
    return if sprint.project_id == project_id

    errors.add(:sprint, :not_in_project)
  end
end
