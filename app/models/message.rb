# A turn on a case thread: public reply, internal note, or agent (AI)
# turn (handoff §2). Agent turns carry their full prompt/response in
# +metadata+. Messages are never edited or deleted by the AI.
class Message < ApplicationRecord
  include SoftDeletable
  include Audited
  include HumanEnums

  humanizes_enums :kind

  enum :kind, { public_reply: 0, internal_note: 1, agent_turn: 2 }, default: :public_reply, prefix: true
  enum :direction, { outbound: 0, inbound: 1 }, default: :outbound, prefix: true

  belongs_to :case, inverse_of: :messages
  belongs_to :author, -> { with_deleted }, polymorphic: true, optional: true

  has_many_attached :files
  include AttachableValidation

  validates :body, presence: true

  after_create :stamp_first_response
  after_create :reopen_conversation_on_citizen_reply
  after_create_commit :notify_contact_by_email
  after_create_commit :enqueue_sentiment_analysis
  after_create_commit :publish_message_webhook

  def author_display_name
    return I18n.t("messages.author.system") if author.nil?
    author.respond_to?(:name) ? author.name : author.to_s
  end

  def from_citizen?
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

  # A citizen reply while we wait on them puts the case back in progress.
  def reopen_conversation_on_citizen_reply
    return unless direction_inbound? && from_citizen? && self.case.status_waiting_on_citizen?
    self.case.transition_to!(:in_progress)
  end

  # Outbound public answers (human or AI) are mailed to the contact.
  def notify_contact_by_email
    return unless direction_outbound? && (kind_public_reply? || kind_agent_turn?)
    return if self.case.contact.email.blank?
    CaseMailer.public_reply(self).deliver_later
  end

  def enqueue_sentiment_analysis
    SentimentJob.perform_later(self) if direction_inbound? && Llm.enabled?
  end

  # Internal notes never leave the deployment — not even as webhooks.
  def publish_message_webhook
    return if kind_internal_note?
    Webhooks.publish("case.message_added", Webhooks.case_payload(self.case).merge(
      message: { id: id, kind: kind, direction: direction, author_type: author_type,
                 body: body, created_at: created_at.utc.iso8601(3) }
    ))
  end
end
