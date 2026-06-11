# A target (Lead/Contact) enrolled in a sequence. The SequenceRunnerJob
# advances it: send the due step, schedule the next, complete when steps
# run out.
class SequenceEnrollment < ApplicationRecord
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
    return if recipient_email.blank? || !step.channel_email?
    CrmMailer.sequence_step(self, step).deliver_later
  end
end
