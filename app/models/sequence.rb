# An automated multi-step outreach (v1.2 CRM). Enroll a Lead or Contact;
# the SequenceRunnerJob sends each step in turn through the comms gateway.
class Sequence < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited

  has_many :sequence_steps, -> { order(:position) }, dependent: nil, inverse_of: :sequence
  has_many :sequence_enrollments, dependent: nil

  accepts_nested_attributes_for :sequence_steps, allow_destroy: true

  validates :name, presence: true
  validate :has_at_least_one_step

  scope :active, -> { where(active: true) }

  def ordered_steps
    sequence_steps.sort_by(&:position)
  end

  # Enroll a target (Lead/Contact); the first step fires after its delay.
  def enroll!(target)
    first = ordered_steps.first
    sequence_enrollments.create!(
      enrollable: target,
      current_step_position: 0,
      status: :active,
      next_run_at: first ? Time.current + first.delay_days.days : nil
    )
  end

  private

  def has_at_least_one_step
    errors.add(:base, :no_steps) if sequence_steps.reject(&:marked_for_destruction?).empty?
  end
end
