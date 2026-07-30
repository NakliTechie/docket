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
  # Stable pointer to the next step to deliver (M5). Nullified if that step is
  # deleted, so a removed step ends the run cleanly rather than shifting an
  # index onto the wrong step. current_step_position is a display-only
  # "steps delivered" counter.
  belongs_to :current_step, class_name: "SequenceStep", optional: true
  has_many :sequence_deliveries, dependent: nil

  scope :due, -> { status_active.where("next_run_at <= ?", Time.current) }

  def due_step
    current_step
  end

  # Send the current step (if any), then schedule the next or complete.
  # Returns true if a step was delivered.
  def advance!
    advanced = false
    with_lock do
      # The due scope is only a candidate list. Re-check under the row lock so
      # two overlapping sweeps cannot advance consecutive steps at once.
      next unless status_active? && next_run_at.present? && next_run_at <= Time.current

      step = due_step
      unless step
        complete!
        next
      end

      sequence_deliveries.create!(delivery_attributes(step))

      # Re-resolve "next" from the live ordered list, so a deletion elsewhere
      # can't shift us onto the wrong step.
      ordered_steps = sequence.ordered_steps
      index = ordered_steps.index(step)
      next_step = index ? ordered_steps[index + 1] : nil
      update!(
        current_step: next_step,
        current_step_position: current_step_position + 1,
        next_run_at: next_step ? Time.current + next_step.delay_days.days : nil,
        status: next_step ? :active : :completed
      )
      advanced = true
    end
    advanced
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

  def delivery_attributes(step)
    if step.channel_sms?
      sms_delivery_attributes(step)
    else
      email_delivery_attributes(step)
    end
  end

  def email_delivery_attributes(step)
    recipient = recipient_email.presence
    {
      tenant: tenant,
      sequence_step: step,
      channel: "email",
      recipient: recipient,
      status: recipient ? :pending : :skipped,
      last_error: ("recipient has no email" unless recipient),
      payload: {
        "subject" => step.render_subject(interpolation_vars).presence || sequence.name,
        "body" => step.render_body(interpolation_vars)
      }
    }
  end

  # Marketing SMS is consent-gated (DPDP / TRAI-DLT). Eligibility is captured
  # when the outbox row is created so a later contact edit cannot change what
  # this already-advanced step meant to send.
  def sms_delivery_attributes(step)
    recipient = recipient_phone.presence
    connector = Comms::SmsGateway.default_connector
    reason =
      if recipient.blank?
        "recipient has no phone"
      elsif !recipient_sms_consent?
        "recipient has not consented to SMS"
      elsif connector.nil?
        "no SMS connector is configured"
      end

    {
      tenant: tenant,
      sequence_step: step,
      connector: connector,
      channel: "sms",
      recipient: recipient,
      status: reason ? :skipped : :pending,
      last_error: reason,
      payload: { "variables" => interpolation_vars }
    }
  end
end
