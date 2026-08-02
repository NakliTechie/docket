class CallRecord < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  STATUSES = %w[received ringing in_progress completed failed busy no_answer cancelled].freeze

  belongs_to :case
  belongs_to :contact
  belongs_to :connector

  validates :provider_call_id, :from_number, presence: true
  validates :provider_call_id, length: { maximum: 255 }
  validates :from_number, :to_number, length: { maximum: 64 }, allow_blank: true
  validates :recording_url, length: { maximum: 2_000 }, allow_blank: true
  validates :transcript, length: { maximum: 100_000 }, allow_blank: true
  validates :provider_call_id, uniqueness: { scope: %i[tenant_id connector_id] }
  validates :status, inclusion: { in: STATUSES }
  validates :duration_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :recording_url_is_http
  validates_same_tenant :case, :contact, :connector

  private

  def recording_url_is_http
    return if recording_url.blank?

    uri = URI.parse(recording_url)
    valid = uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.blank?
    errors.add(:recording_url, :invalid) unless valid
  rescue URI::InvalidURIError
    errors.add(:recording_url, :invalid)
  end
end
