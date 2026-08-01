class Notification < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  enum :kind, {
    assignment: 0, sla_risk: 1, sla_breach: 2, mention: 3, watched_work: 4, escalation: 5
  }, prefix: true
  enum :severity, { info: 0, warning: 1, critical: 2 }, prefix: true
  enum :email_status, { pending: 0, attempting: 1, delivered: 2, failed: 3, unavailable: 4 },
       prefix: :email

  belongs_to :user, -> { with_deleted }
  belongs_to :notifiable, polymorphic: true
  belongs_to :actor, -> { with_deleted }, polymorphic: true, optional: true

  validates :kind, :severity, :dedupe_key, :title, :body, :last_occurred_at, presence: true
  validates :dedupe_key, uniqueness: { scope: %i[tenant_id user_id] }
  validates :occurrences, numericality: { only_integer: true, greater_than: 0 }
  validates :email_delivery_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(last_occurred_at: :desc, id: :desc) }

  after_create_commit :broadcast_badge
  after_update_commit :broadcast_badge,
                      if: -> { saved_change_to_read_at? || saved_change_to_occurrences? }

  def unread? = read_at.nil?

  def mark_read!
    update!(read_at: Time.current) if unread?
  end

  def claim_email_delivery!
    with_lock do
      next false unless email_pending? && unread? && user.active?
      next false if email_delivery_count >= occurrences

      update!(email_status: :attempting, email_claimed_at: Time.current,
              email_attempts: email_attempts + 1, email_last_error: nil)
      true
    end
  end

  def mark_email_delivered!
    update!(email_status: :delivered, emailed_at: Time.current,
            email_delivery_count: occurrences, email_last_error: nil)
  end

  def mark_email_failed!(error)
    update!(email_status: :failed, email_last_error: error.to_s.truncate(500))
  end

  def mark_email_unavailable!
    update!(email_status: :unavailable, email_last_error: "outbound email is not configured")
  end

  def recover_stale_email_claim!
    with_lock do
      return unless email_attempting? && email_claimed_at&.<(1.hour.ago)

      update!(email_status: :pending, email_last_error: "stale email claim recovered")
    end
  end

  def localized_title
    I18n.t("notifications.events.#{kind}.title", **translation_variables, default: title)
  end

  def localized_body
    I18n.t("notifications.events.#{kind}.body", **translation_variables, default: body)
  end

  private

  def translation_variables
    metadata.to_h.symbolize_keys
  end

  def broadcast_badge
    broadcast_replace_to(
      user, :notifications, target: "notification-badge",
      partial: "notifications/badge", locals: { user: user }
    )
  end
end
