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
  include TenantReferentialIntegrity
  include HasCustomFields

  has_custom_fields_for :work_items

  humanizes_enums :kind, :priority

  enum :kind, { task: 0, story: 1, bug: 2, epic: 3 }, default: :task, prefix: true
  # Same vocabulary as Case#priority so one person reading both surfaces isn't
  # translating between two scales.
  enum :priority, { low: 0, normal: 1, high: 2, urgent: 3 }, default: :normal, prefix: true

  # with_deleted like every sibling below: a project is soft-deletable, and
  # deleting one must not orphan its items. Without this, once the project is
  # hidden `work_item.project` is nil and #reference raises — 500-ing the work
  # item page, the whole API collection, and any case page linking the item.
  belongs_to :project, -> { with_deleted }
  belongs_to :workflow_state, -> { with_deleted }
  belongs_to :assignee, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :reporter, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :parent, -> { with_deleted }, class_name: "WorkItem", optional: true
  belongs_to :sprint, -> { with_deleted }, optional: true

  # dependent: nil for the same reason as Sprint#work_items — soft-deleting a
  # parent used to permanently flatten the hierarchy, and restoring it left the
  # parent childless.
  has_many :children, class_name: "WorkItem", foreign_key: :parent_id, dependent: nil,
           inverse_of: :parent
  has_many :work_comments, -> { order(:created_at) }, dependent: :destroy
  has_many :work_links, dependent: :destroy
  has_many :work_watches, dependent: :destroy
  has_many :watchers, through: :work_watches, source: :user
  has_many :audit_entries, as: :auditable, dependent: nil
  has_many :approval_requests, as: :subject, dependent: :destroy
  has_many :outgoing_relations, class_name: "WorkItemRelation", foreign_key: :source_id,
                                dependent: nil, inverse_of: :source
  has_many :incoming_relations, class_name: "WorkItemRelation", foreign_key: :target_id,
                                dependent: nil, inverse_of: :target
  has_many_attached :files
  include AttachableValidation

  validates :title, presence: true
  validates :estimate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :parent_is_not_self_or_descendant
  validates_same_tenant :assignee, :reporter, :parent, :sprint, :workflow_state
  validate :parent_belongs_to_project
  validate :state_belongs_to_project
  validate :sprint_belongs_to_project

  before_validation :assign_number, on: :create
  before_validation :apply_default_assignment, on: :create
  before_save :stamp_closed_at, if: :workflow_state_id_changed?
  after_update_commit :echo_state_to_linked_cases, if: :saved_change_to_workflow_state_id?
  after_create_commit :publish_created
  after_create_commit :notify_assignment, if: :assignee_id?
  after_update_commit :publish_transitioned, if: :saved_change_to_workflow_state_id?
  after_update_commit :notify_assignment, if: :saved_change_to_assignee_id?
  after_update_commit :notify_watchers, if: :saved_change_to_workflow_state_id?

  scope :open, -> { joins(:workflow_state).where.not(workflow_states: { category: :done }) }
  scope :closed, -> { joins(:workflow_state).where(workflow_states: { category: :done }) }
  scope :assigned_to, ->(user) { where(assignee: user) }
  scope :visible_to, ->(user, manage: false) {
    joins(:project).merge(Project.visible_to(user, manage: manage))
  }
  # A tracker you cannot search is not usable for a day. source_key is included
  # so a migrated Jira key (PROJ-123) still finds its item.
  scope :search, ->(q) {
    next all if q.blank?

    term = "%#{sanitize_sql_like(q.strip.downcase)}%"
    where("LOWER(work_items.title) LIKE :t ESCAPE '\\' OR LOWER(work_items.description) LIKE :t ESCAPE '\\' " \
          "OR LOWER(work_items.source_key) LIKE :t ESCAPE '\\'", t: term)
  }

  def reference = "#{project.key}-#{number}"

  def display_label = "#{reference} #{title}"

  def done? = workflow_state&.category_done?

  def open_blockers
    incoming_relations.where(relation_type: "blocks").includes(:source)
                      .map(&:source).reject(&:done?)
  end

  # The single transition point, so every move is audited and closed_at stays
  # honest — mirrors Case#transition_to! rather than inventing a second idiom.
  def transition_to!(state)
    update!(workflow_state: state)
  end

  def guarded_transition_to(state, requested_by: nil)
    if ApprovalGate.guarded_work_transition?(self, state) &&
       !ApprovalGate.work_transition_cleared?(self, state)
      ApprovalGate.submit_work_transition!(self, state, requested_by: requested_by)
      return false
    end

    transition_to!(state)
    true
  end

  private

  def assign_number
    self.number ||= project&.next_item_number!
    self.workflow_state ||= project&.default_state
  end

  def apply_default_assignment
    return if assignee_id? || project.nil? || Imports::Mode.running?

    self.assignee = project.work_assignment_rules.find_by(work_kind: kind)&.assignee
  end

  def stamp_closed_at
    return if Imports::Mode.running?

    self.closed_at = done? ? Time.current : nil
  end

  # An agent watching a case should not have to open the tracker to learn the
  # engineering work finished. Internal note only — the customer never asked
  # for a work item and should not be told about one.
  def publish_created
    return if Imports::Mode.running?

    Webhooks.publish("work_item.created", Webhooks.work_item_payload(self))
  end

  def publish_transitioned
    return if Imports::Mode.running?

    Webhooks.publish("work_item.transitioned", Webhooks.work_item_payload(self))
  end

  def notify_assignment
    Notifications::Events.work_assigned(self)
  end

  def notify_watchers
    Notifications::Events.watched_work(self, event: :transitioned)
  end

  def echo_state_to_linked_cases
    return if Imports::Mode.running?

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
    # On create, parent_id is still blank for `item.parent = item` — the FK is
    # written after the id exists — so check the OBJECT too or the record saves
    # as its own parent and any ancestor walk never terminates.
    if parent.present? && parent.equal?(self)
      errors.add(:parent, :cannot_be_self)
      return
    end
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

  def parent_belongs_to_project
    return if parent.blank? || project_id.blank?
    return if parent.project_id == project_id

    errors.add(:parent, :not_in_project)
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
