class BusinessCalendarWindow < ApplicationRecord
  belongs_to :business_calendar, inverse_of: :business_calendar_windows

  validates :weekday, inclusion: { in: 0..6 }
  validates :starts_minute, :ends_minute,
            numericality: { only_integer: true, greater_than_or_equal_to: 0,
                            less_than_or_equal_to: 1440 }
  validate :ends_after_start
  validate :does_not_overlap

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

  def ends_after_start
    return if starts_minute.nil? || ends_minute.nil? || ends_minute > starts_minute

    errors.add(:ends_minute, :greater_than, count: starts_minute)
  end

  def does_not_overlap
    return if business_calendar.nil? || weekday.nil? || starts_minute.nil? || ends_minute.nil?

    siblings = business_calendar.business_calendar_windows.reject do |window|
      window.equal?(self) || window.marked_for_destruction?
    end
    if siblings.any? do |window|
      window.weekday == weekday && starts_minute < window.ends_minute && ends_minute > window.starts_minute
    end
      errors.add(:base, :overlap)
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
