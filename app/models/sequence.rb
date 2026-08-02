# An automated multi-step outreach (v1.2 CRM). Enroll a Lead or Contact;
# the SequenceRunnerJob sends each step in turn through the comms gateway.
class Sequence < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  has_many :sequence_steps, -> { order(:position) }, dependent: nil, inverse_of: :sequence
  has_many :sequence_enrollments, dependent: nil
  belongs_to :owner, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :business_calendar, optional: true

  accepts_nested_attributes_for :sequence_steps, allow_destroy: true

  validates :name, presence: true
  validate :has_at_least_one_step
  validate :manual_steps_have_owner

  scope :active, -> { where(active: true) }

  def ordered_steps
    sequence_steps.sort_by(&:position)
  end

  def delivery_analytics
    deliveries = SequenceDelivery.joins(:sequence_enrollment)
                                 .where(sequence_enrollments: { sequence_id: id })
    emails = deliveries.where(channel: "email").where.not(delivered_at: nil)
    sent = emails.count
    opened = emails.where.not(opened_at: nil).count
    clicked = emails.where.not(clicked_at: nil).count
    replied = emails.where.not(replied_at: nil).count
    {
      emails_sent: sent,
      opened: opened,
      clicked: clicked,
      replied: replied,
      open_rate: percentage(opened, sent),
      click_rate: percentage(clicked, sent),
      reply_rate: percentage(replied, sent),
      manual_activities: deliveries.where(channel: %w[call manual_task]).count
    }
  end

  # Enroll a target (Lead/Contact); the first step fires after its delay.
  def enroll!(target)
    existing = sequence_enrollments.status_active.find_by(enrollable: target)
    return existing if existing

    first = ordered_steps.first
    sequence_enrollments.create!(
      enrollable: target,
      current_step: first, # stable pointer to the next step to deliver (M5)
      current_step_position: 0,
      status: :active,
      next_run_at: first&.scheduled_at(Time.current)
    )
  rescue ActiveRecord::RecordNotUnique
    sequence_enrollments.status_active.find_by!(enrollable: target)
  end

  private

  def has_at_least_one_step
    errors.add(:base, :no_steps) if sequence_steps.reject(&:marked_for_destruction?).empty?
  end

  def manual_steps_have_owner
    manual = sequence_steps.reject(&:marked_for_destruction?)
                           .any? { |step| step.channel_call? || step.channel_manual_task? }
    errors.add(:owner, :blank) if manual && owner.blank?
  end

  def percentage(numerator, denominator)
    return 0.0 if denominator.zero?

    (numerator * 100.0 / denominator).round(1)
  end
end
