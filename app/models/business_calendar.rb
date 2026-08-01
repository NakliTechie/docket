class BusinessCalendar < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  has_many :business_calendar_windows, -> { order(:weekday, :starts_minute) },
           dependent: :destroy, inverse_of: :business_calendar
  has_many :business_calendar_exceptions, -> { order(:on_date) },
           dependent: :destroy, inverse_of: :business_calendar
  has_many :sla_policies, dependent: :restrict_with_error

  accepts_nested_attributes_for :business_calendar_windows, allow_destroy: true,
                                reject_if: ->(attributes) {
                                  %w[weekday starts_at starts_minute ends_at ends_minute]
                                    .all? { |field| attributes[field].blank? }
                                }
  accepts_nested_attributes_for :business_calendar_exceptions, allow_destroy: true,
                                reject_if: ->(attributes) {
                                  %w[on_date name starts_at starts_minute ends_at ends_minute]
                                    .all? { |field| attributes[field].blank? }
                                }

  validates :name, presence: true,
            uniqueness: { scope: :tenant_id, case_sensitive: false }
  validates :time_zone, presence: true
  validate :time_zone_exists
  validate :has_a_working_window

  before_save :demote_other_defaults, if: :is_default?

  def self.default
    find_by(is_default: true) || order(:id).first
  end

  def zone
    ActiveSupport::TimeZone[time_zone] || ActiveSupport::TimeZone["UTC"]
  end

  def windows_for(date)
    exception = business_calendar_exceptions.detect { |entry| entry.on_date == date }
    return [] if exception&.closed?
    return [ exception.minute_range ] if exception

    business_calendar_windows.select { |window| window.weekday == date.wday }
                             .map(&:minute_range)
  end

  private

  def time_zone_exists
    errors.add(:time_zone, :invalid) if ActiveSupport::TimeZone[time_zone].nil?
  end

  def has_a_working_window
    live = business_calendar_windows.reject(&:marked_for_destruction?)
    errors.add(:business_calendar_windows, :blank) if live.empty?
  end

  def demote_other_defaults
    self.class.where.not(id: id).where(is_default: true).find_each do |calendar|
      calendar.update!(is_default: false)
    end
  end
end
