# A comment on a work item. Deliberately NOT the service desk's Message: a
# Message carries channel, direction, public-vs-internal and customer delivery
# semantics that make no sense on an internal work item. Overloading it would
# make both models lie.
class WorkComment < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  belongs_to :work_item
  # Human and machine collaborators use the same explicit attribution model.
  # Both User and ServiceAccount are soft-deletable, so historical comments
  # keep resolving after their author is deactivated.
  belongs_to :author, -> { with_deleted }, polymorphic: true, optional: true

  has_many :audit_entries, as: :auditable, dependent: nil

  validates :body, presence: true
  validates :source_author_name, presence: true, if: -> { author.nil? }

  scope :visible_to, ->(user, manage: false) {
    joins(work_item: :project).merge(Project.visible_to(user, manage: manage))
  }

  after_create_commit :publish_commented
  after_create_commit :notify_collaborators

  def display_label = "comment on #{work_item&.reference}"

  def author_display_name
    author&.respond_to?(:name) ? author.name : source_author_name
  end

  private

  def publish_commented
    return if Imports::Mode.running?

    Webhooks.publish("work_item.commented",
                     Webhooks.work_item_payload(work_item).merge(
                       comment_id: id, author_type: author_type, author_id: author_id
                     ))
  end

  def notify_collaborators
    Notifications::Events.mentions(self)
    Notifications::Events.watched_work(work_item, event: :commented, source: self)
  end
end
