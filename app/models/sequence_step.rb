# One step of a sequence. Email and SMS use the durable delivery outbox;
# call/manual_task create a PG2 Activity in the sequence owner's rep queue.
# Body/subject support {{var}} interpolation, same syntax as Macros.
class SequenceStep < ApplicationRecord
  include SoftDeletable
  include Audited

  VARIABLES = %w[
    name contact_name first_name company_name email phone owner_name owner_email
    sequence_name deal_name today
  ].freeze
  TEMPLATES = {
    "introduction" => {
      subject: "A quick introduction, {{first_name}}",
      body: "Hi {{first_name}},\n\nI wanted to introduce myself and learn more about {{company_name}}."
    },
    "follow_up" => {
      subject: "Following up, {{first_name}}",
      body: "Hi {{first_name}},\n\nI wanted to follow up on my previous note. Is this a useful time to talk?"
    },
    "check_in" => {
      subject: "Checking in about {{deal_name}}",
      body: "Hi {{first_name}},\n\nDo you have any questions about {{deal_name}} that I can help with?"
    }
  }.freeze

  enum :channel, { email: 0, sms: 1, call: 2, manual_task: 3 }, default: :email, prefix: true

  belongs_to :sequence, -> { with_deleted }, inverse_of: :sequence_steps

  validates :body, presence: true
  validates :delay_days, numericality: { greater_than_or_equal_to: 0 }
  validates :delay_hours, numericality: { greater_than_or_equal_to: 0, less_than: 24 }
  validates :template_key, inclusion: { in: TEMPLATES.keys }, allow_blank: true

  before_validation :apply_template

  def render_subject(vars)
    interpolate(subject.presence || "", vars)
  end

  def render_body(vars)
    interpolate(body, vars)
  end

  # Days remain calendar offsets. When business timing is enabled, hours count
  # only inside the selected calendar and delivery never starts while closed.
  def scheduled_at(from)
    return from + delay_days.days + delay_hours.hours unless use_business_hours?

    calendar = sequence.business_calendar || BusinessCalendar.default
    return from + delay_days.days + delay_hours.hours unless calendar

    opening = BusinessTime.next_opening(calendar: calendar, at: from + delay_days.days)
    BusinessTime.add_minutes(calendar: calendar, from: opening, minutes: delay_hours * 60)
  end

  private

  def apply_template
    template = TEMPLATES[template_key]
    return unless template

    self.subject = template.fetch(:subject) if subject.blank?
    self.body = template.fetch(:body) if body.blank?
  end

  def interpolate(text, vars)
    text.to_s.gsub(/\{\{\s*(\w+)\s*\}\}/) do
      key = Regexp.last_match(1)
      vars.key?(key) ? vars[key].to_s : Regexp.last_match(0)
    end
  end
end
