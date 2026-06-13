# The anchor object (handoff §2). Status transitions are enforced here
# and only here — every status change in the app goes through
# #transition_to!, which stamps lifecycle timestamps and validates the
# move against TRANSITIONS.
class Case < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include Labelable
  include HumanEnums

  humanizes_enums :status, :priority, :channel

  class InvalidTransition < StandardError; end

  # Citizen-friendly, unguessable: no 0/O/1/I/L/U ambiguity or lookalikes.
  TRACKING_ALPHABET = %w[A B C D E F G H J K M N P Q R S T V W X Y Z 2 3 4 5 6 7 8 9].freeze

  # Locked lifecycle: new → triaged → in_progress → waiting_on_citizen →
  # resolved → closed, plus reopened (handoff §2).
  TRANSITIONS = {
    "new"                => %w[triaged in_progress],
    "triaged"            => %w[in_progress waiting_on_citizen resolved],
    "in_progress"        => %w[waiting_on_citizen resolved],
    "waiting_on_citizen" => %w[in_progress resolved],
    "resolved"           => %w[closed reopened],
    "closed"             => %w[reopened],
    "reopened"           => %w[in_progress waiting_on_citizen resolved]
  }.freeze

  OPEN_STATUSES = %w[new triaged in_progress waiting_on_citizen reopened].freeze

  enum :status, { new: 0, triaged: 1, in_progress: 2, waiting_on_citizen: 3,
                  resolved: 4, closed: 5, reopened: 6 }, default: :new, prefix: true
  enum :priority, { low: 0, normal: 1, high: 2, urgent: 3 }, default: :normal, prefix: true
  enum :channel, { web_portal: 0, email: 1, api: 2, staff: 3, phone: 4, walk_in: 5 },
       default: :web_portal, prefix: true

  belongs_to :contact, -> { with_deleted }
  belongs_to :queue, -> { with_deleted }, class_name: "CaseQueue", optional: true
  belongs_to :assignee, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :category, -> { with_deleted }, optional: true
  belongs_to :sla_policy, -> { with_deleted }, optional: true
  # Which connector ingested this case (nil for portal/email/manual/API).
  belongs_to :source_connector, class_name: "Connector", optional: true

  has_many :messages, dependent: nil, inverse_of: :case
  has_many :audit_entries, as: :auditable, dependent: nil

  before_validation :ensure_tracking_id, on: :create
  before_validation :apply_default_sla_policy, on: :create
  before_save :compute_sla_due_dates, if: :sla_inputs_changed?
  after_create_commit :enqueue_agent_triage
  after_create_commit :publish_created_webhook

  validates :subject, presence: true
  validates :tracking_id, presence: true, uniqueness: { scope: :tenant_id }
  validate :status_changed_through_state_machine, on: :update
  # Only block ASSIGNING to an inactive user — a case keeps an assignee who
  # later goes inactive (unchanged assignee_id) so it stays editable.
  validate :assignee_must_be_active, if: -> { assignee_id.present? && will_save_change_to_assignee_id? }

  scope :open_cases, -> { where(status: OPEN_STATUSES) }
  # A breach is also real when the case left the open set (was resolved /
  # closed) after missing its deadline — otherwise a case resolved inside
  # the 5-minute sweep window after going overdue is never flagged (M18).
  scope :overdue_first_response, -> {
    base = where(first_response_breached: false).where.not(first_response_due_at: nil)
    still_open = base.where(first_responded_at: nil, status: OPEN_STATUSES)
                     .where("first_response_due_at < ?", Time.current)
    responded_late = base.where.not(first_responded_at: nil)
                         .where("first_responded_at > first_response_due_at")
    still_open.or(responded_late)
  }
  scope :overdue_resolution, -> {
    base = where(resolution_breached: false).where.not(resolution_due_at: nil)
    still_open = base.where(status: OPEN_STATUSES).where("resolution_due_at < ?", Time.current)
    resolved_late = base.where.not(resolved_at: nil).where("resolved_at > resolution_due_at")
    still_open.or(resolved_late)
  }
  scope :search, ->(q) {
    next all if q.blank?
    term = "%#{sanitize_sql_like(q.strip.downcase)}%"
    where("LOWER(cases.subject) LIKE :t OR LOWER(cases.tracking_id) LIKE :t OR LOWER(cases.description) LIKE :t", t: term)
  }

  def self.generate_tracking_id
    segment = -> { Array.new(4) { TRACKING_ALPHABET[SecureRandom.random_number(TRACKING_ALPHABET.size)] }.join }
    "DKT-#{segment.call}-#{segment.call}"
  end

  def can_transition_to?(new_status)
    TRANSITIONS.fetch(status, []).include?(new_status.to_s)
  end

  def transition_to!(new_status, actor: nil)
    new_status = new_status.to_s
    return self if status == new_status

    unless can_transition_to?(new_status)
      raise InvalidTransition, "cannot transition case from #{status} to #{new_status}"
    end

    previous_status = status
    @transitioning = true
    self.status = new_status
    case new_status
    when "resolved"
      self.resolved_at = Time.current
    when "closed"
      self.closed_at = Time.current
    when "reopened"
      self.reopened_at = Time.current
      self.reopen_count += 1
      self.resolved_at = nil
      self.closed_at = nil
      reset_resolution_sla_on_reopen
    end
    save!
    publish_status_webhooks(previous_status)
    self
  ensure
    @transitioning = false
  end

  def transition_to(new_status, actor: nil)
    transition_to!(new_status, actor: actor)
  rescue InvalidTransition, ActiveRecord::RecordInvalid
    false
  end

  def open?
    OPEN_STATUSES.include?(status)
  end

  def record_first_response!(at: Time.current)
    update!(first_responded_at: at) if first_responded_at.nil?
  end

  private

  def ensure_tracking_id
    return if tracking_id.present?
    candidate = nil
    10.times do
      candidate = self.class.generate_tracking_id
      break unless self.class.with_deleted.exists?(tracking_id: candidate)
      candidate = nil
    end
    self.tracking_id = candidate
  end

  def apply_default_sla_policy
    self.sla_policy ||= SlaPolicy.default
  end

  # Reopening starts a fresh resolution clock from the reopen moment, so
  # the sweep doesn't instantly mark a (possibly long-resolved) case
  # breached against its stale original due date (M17). The sticky
  # resolution_breached flag is left as-is — it is history.
  def reset_resolution_sla_on_reopen
    target = sla_policy&.target_for(priority)
    self.resolution_due_at = target ? (reopened_at + target.resolution_minutes.minutes) : nil
  end

  def sla_inputs_changed?
    new_record? || will_save_change_to_priority? || will_save_change_to_sla_policy_id?
  end

  def compute_sla_due_dates
    target = sla_policy&.target_for(priority)
    base = created_at || Time.current
    if target.nil?
      self.first_response_due_at = nil unless first_responded_at
      self.resolution_due_at = nil unless resolved_at
      return
    end
    self.first_response_due_at = base + target.first_response_minutes.minutes if first_responded_at.nil?
    self.resolution_due_at = base + target.resolution_minutes.minutes if resolved_at.nil?
  end

  # Status mutations must come through #transition_to! — the single
  # state-machine location (handoff §2).
  def status_changed_through_state_machine
    return unless will_save_change_to_status?
    errors.add(:status, :must_use_state_machine) unless @transitioning
  end

  def assignee_must_be_active
    errors.add(:assignee, :inactive) unless assignee&.active?
  end

  # Citizen-originated cases get the AI triage/draft/resolve loop when a
  # model endpoint is configured; silently nothing otherwise.
  def enqueue_agent_triage
    return unless channel_web_portal? || channel_email? || channel_api?
    CaseAgentJob.perform_later(self) if Llm.enabled?
  end

  def publish_created_webhook
    Webhooks.publish("case.created", Webhooks.case_payload(self))
  end

  def publish_status_webhooks(previous_status)
    payload = Webhooks.case_payload(self).merge(previous_status: previous_status)
    Webhooks.publish("case.status_changed", payload)
    Webhooks.publish("case.resolved", payload) if status_resolved?
  end
end
