# One step of a sequence: wait delay_days, then send a templated message
# through the channel (email only in v1; the enum leaves room for the
# v1.1 SMS gateway adapter). Body/subject support {{var}} interpolation,
# same syntax as Macros.
class SequenceStep < ApplicationRecord
  include SoftDeletable
  include Audited

  VARIABLES = %w[contact_name company_name].freeze

  enum :channel, { email: 0 }, default: :email, prefix: true

  belongs_to :sequence, -> { with_deleted }, inverse_of: :sequence_steps

  validates :body, presence: true
  validates :delay_days, numericality: { greater_than_or_equal_to: 0 }

  def render_subject(vars)
    interpolate(subject.presence || "", vars)
  end

  def render_body(vars)
    interpolate(body, vars)
  end

  private

  def interpolate(text, vars)
    text.to_s.gsub(/\{\{\s*(\w+)\s*\}\}/) do
      key = Regexp.last_match(1)
      vars.key?(key) ? vars[key].to_s : Regexp.last_match(0)
    end
  end
end
