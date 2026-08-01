class CsatSurvey < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :case
  belongs_to :contact, optional: true

  enum :delivery_status, { pending: 0, attempting: 1, delivered: 2, failed: 3, unavailable: 4 },
       prefix: :delivery

  validates :invited_at, presence: true
  validates :score, inclusion: { in: 1..5 }, allow_nil: true
  validates :comment, length: { maximum: 2_000 }
  validates :case_id, uniqueness: { scope: :tenant_id }
  validate :response_is_complete
  validates_same_tenant :case, :contact

  scope :responded, -> { where.not(responded_at: nil) }

  def self.invite!(kase)
    return unless Setting.get("csat_enabled", false) == true
    return if Imports::Mode.running? || kase.contact&.email.blank?

    survey = find_or_create_by!(case: kase) do |record|
      record.contact = kase.contact
      record.invited_at = Time.current
    end
    survey.enqueue_delivery!
    survey
  end

  def enqueue_delivery!
    should_enqueue = with_lock do
      next false if sent_at? || !delivery_pending?
      next false if delivery_enqueued_at? && delivery_enqueued_at > 10.minutes.ago

      update_column(:delivery_enqueued_at, Time.current)
      true
    end
    return unless should_enqueue

    CsatInvitationJob.perform_later(self)
  rescue ActiveJob::EnqueueError
    update_column(:delivery_enqueued_at, nil)
    raise
  end

  def claim_delivery!
    with_lock do
      next false unless delivery_pending?

      update!(delivery_status: :attempting, delivery_claimed_at: Time.current,
              delivery_attempts: delivery_attempts + 1, delivery_last_error: nil)
      true
    end
  end

  def mark_delivery_delivered!
    update!(delivery_status: :delivered, sent_at: Time.current, delivery_last_error: nil)
  end

  def mark_delivery_failed!(error)
    update!(delivery_status: :failed, delivery_last_error: error.to_s.truncate(500))
  end

  def mark_delivery_unavailable!
    update!(delivery_status: :unavailable, delivery_last_error: "outbound email is not configured")
  end

  def recover_stale_delivery_claim!
    with_lock do
      return unless delivery_attempting? && delivery_claimed_at&.<(1.hour.ago)

      update!(delivery_status: :pending, delivery_enqueued_at: nil,
              delivery_last_error: "stale delivery claim recovered")
    end
  end

  def respond!(score:, comment: nil)
    return self if responded_at?

    update!(score: score, comment: comment, responded_at: Time.current)
    self
  end

  private

  def response_is_complete
    return if responded_at.nil? || score.present?

    errors.add(:score, :blank)
  end
end
