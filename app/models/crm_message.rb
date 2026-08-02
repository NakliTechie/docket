class CrmMessage < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include HumanEnums

  SUBJECT_TYPES = %w[Contact Lead Deal].freeze
  EMAIL_PATTERN = URI::MailTo::EMAIL_REGEXP

  humanizes_enums :channel, :direction, :delivery_status

  enum :channel, { email: 0, whatsapp: 1, telegram: 2 }, default: :email, prefix: true
  enum :direction, { outbound: 0, inbound: 1 }, default: :outbound, prefix: true
  enum :delivery_status,
       { pending: 0, attempting: 1, delivered: 2, failed: 3, skipped: 4, recorded: 5 },
       default: :recorded, prefix: true

  belongs_to :subject, polymorphic: true
  belongs_to :author, polymorphic: true, optional: true
  belongs_to :source_connector, class_name: "Connector", optional: true

  has_many_attached :files
  include AttachableValidation

  normalizes :sender_email, with: ->(value) { value.to_s.strip.downcase.presence }
  normalizes :recipient_email, with: ->(value) { value.to_s.strip.downcase.presence }

  validates :subject_type, inclusion: { in: SUBJECT_TYPES }
  validates :body, presence: true, length: { maximum: 100_000 }
  validates :subject_line, length: { maximum: 998 }, allow_nil: true
  validates :sender_email, :recipient_email, format: { with: EMAIL_PATTERN }, allow_nil: true
  validates :email_message_id, uniqueness: { scope: :tenant_id }, allow_nil: true
  validates :external_message_id,
            uniqueness: { scope: %i[tenant_id source_connector_id] }, allow_nil: true
  validates :delivery_status, inclusion: { in: delivery_statuses.keys }
  validate :subject_is_same_tenant
  validate :author_is_same_tenant
  validate :delivery_is_outbound_email

  before_validation :stamp_occurred_at, on: :create
  after_create_commit :enqueue_delivery

  scope :chronological, -> { order(:occurred_at, :id) }
  scope :recent_first, -> { order(occurred_at: :desc, id: :desc) }

  def self.compose(subject:, author:, subject_line:, body:)
    create!(
      subject: subject,
      author: author,
      channel: :email,
      direction: :outbound,
      delivery_status: :pending,
      sender_email: sender_for(author),
      recipient_email: CrmConversation.recipient_email(subject),
      subject_line: subject_line,
      body: body,
      occurred_at: Time.current
    )
  end

  def self.sender_for(author)
    return author.email_address if author.respond_to?(:email_address)

    raw = Setting.get("outbound_email_from", ENV.fetch("DOCKET_MAIL_FROM", "no-reply@docket.local"))
    Mail::Address.new(raw.to_s).address
  end

  def display_author
    return author.name if author&.respond_to?(:name)
    return sender_email if sender_email.present?

    I18n.t("crm_messages.unknown_author")
  end

  def claim_delivery!
    with_lock do
      return false unless delivery_status_pending?

      update!(delivery_status: :attempting, delivery_claimed_at: Time.current,
              delivery_last_error: nil)
      true
    end
  end

  def mark_delivered!
    update!(delivery_status: :delivered, delivered_at: Time.current,
            delivery_last_error: nil)
  end

  def mark_failed!(error)
    update!(delivery_status: :failed, delivery_last_error: error.to_s.truncate(500))
  end

  def mark_skipped!(reason)
    update!(delivery_status: :skipped, delivery_last_error: reason.to_s.truncate(500))
  end

  private

  def stamp_occurred_at
    self.occurred_at ||= Time.current
  end

  def enqueue_delivery
    CrmMessageDeliveryJob.perform_later(id) if delivery_status_pending?
  end

  def subject_is_same_tenant
    return unless SUBJECT_TYPES.include?(subject_type) && subject_id.present?

    owner_tenant = ActsAsTenant.without_tenant do
      subject_type.constantize.unscoped.where(id: subject_id).pick(:tenant_id)
    end
    errors.add(:subject, :cross_tenant) if owner_tenant.present? && owner_tenant != tenant_id
  end

  def author_is_same_tenant
    errors.add(:author, :cross_tenant) if author&.respond_to?(:tenant_id) && author.tenant_id != tenant_id
  end

  def delivery_is_outbound_email
    return unless delivery_status_pending? || delivery_status_attempting?
    return if channel_email? && direction_outbound? && recipient_email.present? && author.present?

    errors.add(:delivery_status, :invalid)
  end
end
