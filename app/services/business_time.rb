class BusinessTime
  MAX_DAYS = 3660

  def self.add_minutes(...) = new(...).add_minutes
  def self.minutes_between(...) = new(...).minutes_between
  def self.next_opening(calendar:, at:) = new(calendar: calendar, from: at).next_opening

  def initialize(calendar:, from:, minutes: nil, to: nil)
    @calendar = calendar
    @from = from
    @minutes = minutes
    @to = to
  end

  def add_minutes
    remaining = Integer(@minutes)
    return @from if remaining.zero?
    raise ArgumentError, "minutes must be non-negative" if remaining.negative?

    cursor = in_zone(@from)
    MAX_DAYS.times do
      windows_for(cursor.to_date).each do |opening, closing|
        cursor = opening if cursor < opening
        next if cursor >= closing

        available = ((closing - cursor) / 60).floor
        return (cursor + remaining.minutes).utc if remaining <= available

        remaining -= available
        cursor = closing
      end
      cursor = start_of_next_day(cursor)
    end
    raise RangeError, "business-time deadline exceeds #{MAX_DAYS} days"
  end

  def minutes_between
    finish = in_zone(@to)
    cursor = in_zone(@from)
    return 0 if finish <= cursor

    total = 0
    MAX_DAYS.times do
      windows_for(cursor.to_date).each do |opening, closing|
        start = [ cursor, opening ].max
        stop = [ finish, closing ].min
        total += ((stop - start) / 60).floor if stop > start
      end
      break if cursor.to_date >= finish.to_date
      cursor = start_of_next_day(cursor)
    end
    total
  end

  def next_opening
    cursor = in_zone(@from)
    MAX_DAYS.times do
      windows_for(cursor.to_date).each do |opening, closing|
        return opening.utc if cursor < opening
        return cursor.utc if cursor < closing
      end
      cursor = start_of_next_day(cursor)
    end
    raise RangeError, "business-time opening exceeds #{MAX_DAYS} days"
  end

  private

  def in_zone(time)
    time.in_time_zone(@calendar.zone)
  end

  def windows_for(date)
    @calendar.windows_for(date).map do |range|
      [ at_minute(date, range.begin), at_minute(date, range.end) ]
    end
  end

  def at_minute(date, minute)
    @calendar.zone.local(date.year, date.month, date.day, minute / 60, minute % 60)
  end

  def start_of_next_day(cursor)
    date = cursor.to_date.next_day
    @calendar.zone.local(date.year, date.month, date.day)
  end
end
