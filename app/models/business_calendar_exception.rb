class BusinessCalendarException < ApplicationRecord
  belongs_to :business_calendar, inverse_of: :business_calendar_exceptions

  validates :on_date, :name, presence: true
  validates :on_date, uniqueness: { scope: :business_calendar_id }
  validate :valid_shape

  def minute_range = starts_minute...ends_minute

  def starts_at = format_minute(starts_minute)
  def ends_at = format_minute(ends_minute)

  def starts_at=(value)
    self.starts_minute = parse_minute(value)
  end

  def ends_at=(value)
    self.ends_minute = parse_minute(value)
  end

  private

  def valid_shape
    if closed?
      errors.add(:base, :closed_with_hours) if starts_minute.present? || ends_minute.present?
      return
    end
    if starts_minute.nil? || ends_minute.nil? || starts_minute.negative? ||
       ends_minute > 1440 || ends_minute <= starts_minute
      errors.add(:base, :invalid_hours)
    end
  end

  def parse_minute(value)
    return if value.blank?

    hour, minute = value.to_s.split(":", 2).map(&:to_i)
    (hour * 60) + minute
  end

  def format_minute(value)
    value && format("%02d:%02d", value / 60, value % 60)
  end
end
