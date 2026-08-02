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
  belongs_to :source_message, class_name: "Message", optional: true
  has_one :assistant_response, class_name: "Message", foreign_key: :source_message_id,
                               dependent: nil, inverse_of: :source_message

  has_many_attached :files
  include AttachableValidation

  validates :body, presence: true
  # DELIBERATELY not scoped to live rows (unlike most SoftDeletable uniqueness
  # rules): this is the idempotent-inbound dedup key. Connectors::Inbound#find_message
  # looks it up with_deleted, so an external message that was ingested once must
  # never be re-ingested even after its Message is soft-deleted. Adding a
  # deleted_at: nil condition here would reopen exactly that re-ingestion hole.
  validates :external_message_id,
            uniqueness: { scope: %i[tenant_id source_connector_id] },
            allow_nil: true
  validates :source_message_id, uniqueness: { scope: :tenant_id }, allow_nil: true
  validates_same_tenant :source_message
  validate :source_message_belongs_to_case

  after_create :stamp_first_response
  after_create :reopen_conversation_on_customer_reply
  after_create_commit :notify_contact_by_email
  after_create_commit :deliver_via_messaging_connector
  after_create_commit :enqueue_sentiment_analysis
  after_create_commit :publish_message_webhook
  after_create_commit :notify_mentions
  after_create_commit :broadcast_to_live_chat
  after_create_commit :enqueue_live_chat_assistant

  def author_display_name
    return source_author_name if source_author_name.present?
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

  def signature = metadata&.dig("signature").presence

  def outbound_body
    [ body, signature ].compact_blank.join("\n\n")
  end

  private

  # First outbound public answer (human or AI) stops the first-response
  # SLA clock.
  def stamp_first_response
    return if Imports::Mode.running?

    return unless direction_outbound? && (kind_public_reply? || kind_agent_turn?)
    self.case.record_first_response!(at: created_at)
  end

  # A customer reply re-engages staff: while we wait on them it goes back to
  # in_progress; on an already-resolved case it reopens it — otherwise the
  # reply lands silently on a resolved case and staff never see it (M13).
  def reopen_conversation_on_customer_reply
    return if Imports::Mode.running?

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
    return if self.case.channel_live_chat? && self.case.live_chat&.active?
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

  def notify_mentions
    Notifications::Events.mentions(self)
  end

  def source_message_belongs_to_case
    return if source_message.blank? || source_message.case_id == case_id

    errors.add(:source_message, :invalid)
  end

  def broadcast_to_live_chat
    live_chat = self.case.live_chat
    return unless live_chat
    return unless kind_public_reply? || kind_agent_turn?

    LiveChatChannel.broadcast_to(live_chat, LiveChatMessageSerializer.call(self))
  end

  def enqueue_live_chat_assistant
    return unless direction_inbound? && self.case.channel_live_chat?
    return unless Setting.get("live_chat_bot_enabled", false) == true && Llm.enabled?

    LiveChatAssistantJob.perform_later(id)
  end
end
