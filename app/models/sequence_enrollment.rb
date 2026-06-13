# A target (Lead/Contact) enrolled in a sequence. The SequenceRunnerJob
# advances it: send the due step, schedule the next, complete when steps
# run out.
class SequenceEnrollment < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  enum :status, { active: 0, completed: 1, cancelled: 2 }, default: :active, prefix: true

  belongs_to :sequence, -> { with_deleted }
  belongs_to :enrollable, -> { with_deleted }, polymorphic: true

  scope :due, -> { status_active.where("next_run_at <= ?", Time.current) }

  def due_step
    sequence.ordered_steps[current_step_position]
  end

  # Send the current step (if any), then schedule the next or complete.
  # Returns true if a step was delivered.
  def advance!
    step = due_step
    return complete! && false if step.nil?

    deliver(step)
    next_step = sequence.ordered_steps[current_step_position + 1]
    update!(
      current_step_position: current_step_position + 1,
      next_run_at: next_step ? Time.current + next_step.delay_days.days : nil,
      status: next_step ? :active : :completed
    )
    true
  end

  def cancel!
    update!(status: :cancelled, next_run_at: nil)
  end

  def recipient_email
    enrollable.try(:email)
  end

  def recipient_phone
    enrollable.try(:phone)
  end

  def recipient_sms_consent?
    !!enrollable.try(:sms_consent)
  end

  def interpolation_vars
    {
      "contact_name" => enrollable.try(:name),
      "company_name" => enrollable.try(:company_name) || enrollable.try(:organisation)&.name
    }
  end

  private

  def complete!
    update!(status: :completed, next_run_at: nil)
  end

  def deliver(step)
    step.channel_sms? ? deliver_sms(step) : deliver_email(step)
  end

  def deliver_email(step)
    return if recipient_email.blank?
    CrmMailer.sequence_step(self, step).deliver_later
  end

  # Marketing SMS is consent-gated (DPDP / TRAI-DLT): send only to a recipient
  # who has a phone AND has opted in, and only if an SMS connector is wired.
  # A missing channel is a silent skip — it must not stall the enrollment, which
  # still advances to the next step (handled by the caller).
  def deliver_sms(step)
    return unless recipient_phone.present? && recipient_sms_consent?

    connector = Comms::SmsGateway.default_connector
    return unless connector

    SmsDeliveryJob.perform_later(connector.id, recipient_phone, interpolation_vars)
  end
end
