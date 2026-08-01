# A workspace in the Work module — the Jira/Linear-class pillar. Owns its own
# workflow states (one team's "In review" is another's "QA"), and mints the
# per-project item numbers that give work items their KEY-123 identity.
class Project < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include TenantReferentialIntegrity
  include HumanEnums

  humanizes_enums :visibility, :kind

  enum :visibility, { tenant_wide: 0, restricted: 1 }, default: :tenant_wide, prefix: true
  # How the project was started: a manually-created project is standard; a won
  # deal opens an onboarding project (DealOnboarding); an OPEN deal opens an
  # engagement project (pre-quote studies) via DealOnboarding mode: :engagement.
  enum :kind, { standard: 0, onboarding: 1, engagement: 2 }, default: :standard, prefix: true

  KEY_FORMAT = /\A[A-Z][A-Z0-9]{1,9}\z/

  # The floor a project needs to be usable on creation. Category drives
  # reporting; several named states may share one.
  DEFAULT_STATES = [
    { name: "Backlog",     category: :todo },
    { name: "Todo",        category: :todo },
    { name: "In progress", category: :in_progress },
    { name: "In review",   category: :in_progress },
    { name: "Done",        category: :done }
  ].freeze

  belongs_to :lead, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :onboarding_deal, -> { with_deleted }, class_name: "Deal", optional: true
  belongs_to :project_template, optional: true

  # dependent: nil, not :destroy — cascading into workflow_states hit their
  # restrict_with_error guard and SoftDeletable#destroy! re-raised it, so
  # deleting any project that held work items was a 500. Soft-deleting a
  # project hides it and everything under it stays intact behind it.
  has_many :workflow_states, -> { order(:position) }, dependent: nil, inverse_of: :project
  # Board columns are edited inline on the project form (name, order, soft WIP
  # limit). `update_only:` does nothing on a has_many, so reject_if is what
  # actually stops the form creating columns — editing a board is not the same
  # act as designing one, and a nested payload should not be able to smuggle a
  # new column in. (No allow_destroy either: removal stays explicit.)
  accepts_nested_attributes_for :workflow_states,
                                reject_if: ->(attrs) { attrs["id"].blank? }
  has_many :work_items, dependent: nil
  has_many :sprints, dependent: nil
  # Memberships are part of a soft-deleted project's recoverable access model.
  # A restore must not silently turn a restricted project into an empty shell.
  has_many :project_memberships, dependent: nil
  has_many :members, through: :project_memberships, source: :user
  has_many :audit_entries, as: :auditable, dependent: nil
  has_many :work_assignment_rules, dependent: nil
  accepts_nested_attributes_for :work_assignment_rules, allow_destroy: true,
                                reject_if: ->(attrs) { attrs["assignee_id"].blank? }

  validates :name, presence: true
  validates :key, presence: true, format: { with: KEY_FORMAT },
            uniqueness: { scope: :tenant_id, case_sensitive: false,
                          conditions: -> { where(deleted_at: nil) } }

  normalizes :key, with: ->(key) { key.to_s.strip.upcase }

  validates_same_tenant :lead, :onboarding_deal, :project_template

  after_create :seed_default_states

  scope :active, -> { where(archived: false) }
  scope :visible_to, ->(user, manage: false) {
    if manage || user&.can?("project:manage")
      all
    elsif user
      membership_projects = ProjectMembership.where(user_id: user.id).select(:project_id)
      where(visibility: visibilities.fetch("tenant_wide")).or(where(id: membership_projects))
    else
      where(visibility: Project.visibilities.fetch("tenant_wide"))
    end
  }

  def display_label = "#{key} — #{name}"

  def default_state = workflow_states.first

  def visible_to?(user, manage: false)
    manage || user&.can?("project:manage") || visibility_tenant_wide? ||
      (user.present? && project_memberships.any? { |membership| membership.user_id == user.id })
  end

  # Project deletion is one recoverable lifecycle event. Children that were
  # live at that instant receive the exact same tombstone; restore clears only
  # that matching stamp, preserving anything deleted earlier on its own.
  def destroy
    return self if deleted?

    result = nil
    transaction do
      stamp = Time.current
      lifecycle_children.each do |association|
        association.with_deleted.where(deleted_at: nil).update_all(deleted_at: stamp)
      end
      result = run_callbacks(:destroy) { update_columns(deleted_at: stamp) && self }
      raise ActiveRecord::Rollback unless result
    end
    result
  end

  def restore!
    stamp = deleted_at
    return self if stamp.blank?

    transaction do
      lifecycle_children.each do |association|
        association.with_deleted.where(deleted_at: stamp).update_all(deleted_at: nil)
      end
      update!(deleted_at: nil)
    end
    self
  end

  # Mint the next KEY-123 number. Locks the project row so two concurrent
  # creates cannot read the same counter — the alternative (MAX(number)+1)
  # races exactly the same way.
  #
  # Self-healing: takes the max of the counter and the highest number actually
  # present, so a bulk import that writes numbers directly (WM/NC2 carries Jira
  # issue numbers across) can't leave the counter behind and start minting
  # duplicates. Deleted items count — their numbers must never be reissued.
  def next_item_number!
    with_lock do
      highest = work_items.with_deleted.maximum(:number).to_i
      self.last_item_number = [ last_item_number.to_i, highest ].max + 1
      save!(validate: false)
      last_item_number
    end
  end

  private

  def lifecycle_children
    [ workflow_states, work_items, sprints ]
  end

  def seed_default_states
    DEFAULT_STATES.each_with_index do |attrs, index|
      workflow_states.create!(name: attrs[:name], category: attrs[:category], position: index)
    end
  end
end
