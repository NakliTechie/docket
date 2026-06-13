# The "Queue" domain object (handoff §2): a routing bucket with
# membership. Class is CaseQueue because ::Queue is a Ruby core class;
# the table, UI vocabulary, and API resource all remain "queues".
class CaseQueue < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  self.table_name = "queues"

  # dependent: nil, not :destroy — soft-delete runs destroy callbacks, so
  # :destroy would hard-delete the memberships while the queue is only
  # soft-deleted. Preserve them so a restored queue keeps its members.
  has_many :queue_memberships, foreign_key: :queue_id, dependent: nil, inverse_of: :queue
  has_many :members, through: :queue_memberships, source: :user
  has_many :cases, foreign_key: :queue_id, dependent: nil, inverse_of: :queue

  before_validation :derive_slug

  validates :name, presence: true, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } }
  validates :slug, presence: true, uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } },
            format: { with: /\A[a-z0-9-]+\z/ }

  def self.default
    find_by(id: Setting.get("default_queue_id"))
  end

  private

  def derive_slug
    self.slug = (slug.presence || name.to_s).parameterize
  end
end
