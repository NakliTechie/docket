# A turn on a case thread: public reply, internal note, or agent (AI)
# turn (handoff §2). Agent turns carry their full prompt/response in
# +metadata+. Messages are never edited or deleted by the AI.
class Message < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include HumanEnums

  humanizes_enums :kind

  enum :kind, { public_reply: 0, internal_note: 1, agent_turn: 2 }, default: :public_reply, prefix: true
  enum :direction, { outbound: 0, inbound: 1 }, default: :outbound, prefix: true

  belongs_to :case, inverse_of: :messages
  belongs_to :author, -> { with_deleted }, polymorphic: true, optional: true
  # Provider delivery identity for inbound replay protection. Scoped by
  # connector because providers may issue the same id in separate accounts.
  belongs_to :source_connector, class_name: "Connector", optional: true

  has_many_attached :files
  include AttachableValidation

  validates :body, presence: true
  validates :external_message_id,
            uniqueness: { scope: %i[tenant_id source_connector_id] },
            allow_nil: true

  after_create :stamp_first_response
  after_create :reopen_conversation_on_customer_reply
  after_create_commit :notify_contact_by_email
  after_create_commit :deliver_via_messaging_connector
  after_create_commit :enqueue_sentiment_analysis
  after_create_commit :publish_message_webhook

  def author_display_name
    return I18n.t("messages.author.system") if author.nil?
    author.respond_to?(:name) ? author.name : author.to_s
  end

  def from_customer?
    author_type == "Contact"
  end

  def sentiment
    metadata&.dig("sentiment")
  end

  def ai_action
    metadata&.dig("ai")
  end

  private

  # First outbound public answer (human or AI) stops the first-response
  # SLA clock.
  def stamp_first_response
    return unless direction_outbound? && (kind_public_reply? || kind_agent_turn?)
    self.case.record_first_response!(at: created_at)
  end

  # A customer reply re-engages staff: while we wait on them it goes back to
  # in_progress; on an already-resolved case it reopens it — otherwise the
  # reply lands silently on a resolved case and staff never see it (M13).
  def reopen_conversation_on_customer_reply
    return unless direction_inbound? && from_customer?

    # Route through the maker-checker gate (W3): if a tenant guards
    # in_progress/reopened, the auto-reopen parks for approval instead of
    # bypassing the gate off the controller path. Unguarded → transitions as
    # before. requested_by nil = system/customer-initiated.
    if self.case.status_waiting_on_customer?
      self.case.guarded_transition_to(:in_progress)
    elsif self.case.status_resolved?
      self.case.guarded_transition_to(:reopened)
    end
  end

  # Outbound public answers (human or AI) are mailed to the contact — unless the
  # case came in over a messaging connector, where the reply goes back out that
  # same channel instead (see #deliver_via_messaging_connector).
  def notify_contact_by_email
    return if Imports::Mode.running?

    return unless direction_outbound? && (kind_public_reply? || kind_agent_turn?)
    return if self.case.source_connector&.ingests?
    return if self.case.contact.email.blank?
    CaseMailer.public_reply(self).deliver_later
  end

  # Outbound public answers on a messaging case (WhatsApp/Telegram) are sent
  # back out through the originating connector — the omnichannel reply loop (PG2).
  def deliver_via_messaging_connector
    return if Imports::Mode.running?

    return unless direction_outbound? && (kind_public_reply? || kind_agent_turn?)
    return unless self.case.source_connector&.ingests?
    ConnectorReplyJob.perform_later(id)
  end

  def enqueue_sentiment_analysis
    return if Imports::Mode.running?

    # Pass the id (not the record) — consistent with the other message jobs and
    # safe if the message is gone by the time the job runs (S9).
    SentimentJob.perform_later(id) if direction_inbound? && Llm.enabled?
  end

  # Internal notes never leave the deployment — not even as webhooks.
  def publish_message_webhook
    return if Imports::Mode.running?

    return if kind_internal_note?
    Webhooks.publish("case.message_added", Webhooks.case_payload(self.case).merge(
      message: { id: id, kind: kind, direction: direction, author_type: author_type,
                 body: body, created_at: created_at.utc.iso8601(3) }
    ))
  end
end
