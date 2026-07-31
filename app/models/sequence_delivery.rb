# Durable outbox/receipt for one sequence step. A row is created in the same
# transaction that advances its enrollment, then claimed before external
# egress. That deliberately gives customer outreach at-most-once attempt
# semantics: an uncertain claim is never replayed and cannot duplicate a send.
class SequenceDelivery < ApplicationRecord
  acts_as_tenant(:tenant)

  enum :status, {
    pending: 0,
    attempting: 1,
    delivered: 2,
    skipped: 3,
    failed: 4
  }, prefix: true

  belongs_to :sequence_enrollment, -> { with_deleted }
  belongs_to :sequence_step, -> { with_deleted }
  belongs_to :connector, optional: true

  validates :channel, inclusion: { in: %w[email sms] }
  validates :sequence_step_id, uniqueness: { scope: :sequence_enrollment_id }
  validate :records_share_tenant

  after_create_commit :enqueue!, if: :status_pending?

  def enqueue!
    SequenceDeliveryJob.perform_later(id)
  rescue StandardError => e
    # The recurring outbox sweep will enqueue this pending row again. Do not
    # turn an enqueue outage into a rollback illusion after the transaction
    # that advanced the enrollment has already committed.
    Rails.logger.warn("[sequence] could not enqueue delivery #{id}: #{e.message}")
  end

  def claim!
    claimed = false
    target = sequence_enrollment.enrollable
    target.with_lock do
      with_lock do
        if status_pending?
          if channel == "email" && !sequence_enrollment.recipient_email_consent?
            update!(status: :skipped, last_error: "email consent withdrawn")
          elsif channel == "sms" && !sequence_enrollment.recipient_sms_consent?
            update!(status: :skipped, last_error: "SMS consent withdrawn")
          else
            update!(status: :attempting, claimed_at: Time.current)
            claimed = true
          end
        end
      end
    end
    claimed
  end

  def mark_delivered!
    update!(status: :delivered, delivered_at: Time.current, last_error: nil)
  end

  def mark_skipped!(reason)
    update!(status: :skipped, last_error: reason.to_s.truncate(250))
  end

  def mark_failed!(error)
    update!(status: :failed, last_error: error.to_s.truncate(250))
  end

  private

  def records_share_tenant
    return if tenant_id.blank?

    if sequence_enrollment && sequence_enrollment.tenant_id != tenant_id
      errors.add(:sequence_enrollment, :different_tenant)
    end
    if sequence_step && sequence_step.sequence&.tenant_id != tenant_id
      errors.add(:sequence_step, :different_tenant)
    end
    if connector && connector.tenant_id != tenant_id
      errors.add(:connector, :different_tenant)
    end
  end
end
