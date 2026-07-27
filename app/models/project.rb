# A workspace in the Work module — the Jira/Linear-class pillar. Owns its own
# workflow states (one team's "In review" is another's "QA"), and mints the
# per-project item numbers that give work items their KEY-123 identity.
class Project < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

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

  has_many :workflow_states, -> { order(:position) }, dependent: :destroy, inverse_of: :project
  # Board columns are edited inline on the project form (name, order, soft WIP
  # limit); creating/removing columns is a separate deliberate act.
  accepts_nested_attributes_for :workflow_states, update_only: true
  has_many :work_items, dependent: :destroy
  has_many :sprints, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :members, through: :project_memberships, source: :user
  has_many :audit_entries, as: :auditable, dependent: nil

  validates :name, presence: true
  validates :key, presence: true, format: { with: KEY_FORMAT },
            uniqueness: { scope: :tenant_id, case_sensitive: false,
                          conditions: -> { where(deleted_at: nil) } }

  normalizes :key, with: ->(key) { key.to_s.strip.upcase }

  after_create :seed_default_states

  scope :active, -> { where(archived: false) }

  def display_label = "#{key} — #{name}"

  def default_state = workflow_states.first

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

  def seed_default_states
    DEFAULT_STATES.each_with_index do |attrs, index|
      workflow_states.create!(name: attrs[:name], category: attrs[:category], position: index)
    end
  end
end
