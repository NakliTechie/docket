# Outbound webhook target (handoff §5): HMAC-SHA256-signed POSTs on
# case lifecycle events, per-endpoint secret, retry with backoff,
# delivery log in the admin UI.
class WebhookEndpoint < ApplicationRecord
  include SoftDeletable
  include Audited

  EVENTS = %w[
    case.created
    case.status_changed
    case.message_added
    case.sla_breached
    case.resolved
  ].freeze

  has_many :webhook_deliveries, dependent: :delete_all

  validates :name, presence: true
  validates :url, presence: true
  validates :secret, presence: true
  validate :events_are_known
  validate :url_is_http

  before_validation :generate_secret, on: :create

  scope :active, -> { where(active: true) }
  scope :subscribed_to, ->(event) { active.select { |e| e.subscribed?(event) } }

  def subscribed?(event)
    events.include?(event.to_s)
  end

  def sign(body)
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"
  end

  private

  def generate_secret
    self.secret ||= "whsec_#{SecureRandom.alphanumeric(40)}"
  end

  def events_are_known
    unknown = Array(events) - EVENTS
    errors.add(:events, :invalid) if unknown.any? || Array(events).empty?
  end

  def url_is_http
    uri = URI.parse(url.to_s)
    unless uri.is_a?(URI::HTTP) && uri.host.present?
      errors.add(:url, :invalid)
      return
    end
    # SSRF guard: reject loopback / link-local / metadata / localhost.
    if (reason = Docket::OutboundUrl.blocked_reason(uri.host))
      errors.add(:url, :blocked, default: "must not point at an internal address (#{reason})")
    end
  rescue URI::InvalidURIError
    errors.add(:url, :invalid)
  end

  def audit_redacted_attributes
    super | %w[secret]
  end
end
