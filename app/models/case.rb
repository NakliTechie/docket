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
  include HasCustomFields

  has_custom_fields_for :cases

  humanizes_enums :status, :priority, :channel

  class InvalidTransition < StandardError; end

  # Customer-friendly, unguessable: no 0/O/1/I/L/U ambiguity or lookalikes.
  TRACKING_ALPHABET = %w[A B C D E F G H J K M N P Q R S T V W X Y Z 2 3 4 5 6 7 8 9].freeze

  # Locked lifecycle: new → triaged → in_progress → waiting_on_customer →
  # resolved → closed, plus reopened (handoff §2).
  TRANSITIONS = {
    "new"                => %w[triaged in_progress],
    "triaged"            => %w[in_progress waiting_on_customer resolved],
    "in_progress"        => %w[waiting_on_customer resolved],
    "waiting_on_customer" => %w[in_progress resolved],
    "resolved"           => %w[closed reopened],
    "closed"             => %w[reopened],
    "reopened"           => %w[in_progress waiting_on_customer resolved]
  }.freeze

  OPEN_STATUSES = %w[new triaged in_progress waiting_on_customer reopened].freeze

  enum :status, { new: 0, triaged: 1, in_progress: 2, waiting_on_customer: 3,
                  resolved: 4, closed: 5, reopened: 6 }, default: :new, prefix: true
  enum :priority, { low: 0, normal: 1, high: 2, urgent: 3 }, default: :normal, prefix: true
  enum :channel, { web_portal: 0, email: 1, api: 2, staff: 3, phone: 4, walk_in: 5,
                   whatsapp: 6, telegram: 7, sms: 8, live_chat: 9 },
       default: :web_portal, prefix: true

  belongs_to :contact, -> { with_deleted }
  belongs_to :queue, -> { with_deleted }, class_name: "CaseQueue", optional: true
  belongs_to :assignee, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :owner, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :category, -> { with_deleted }, optional: true
  belongs_to :sla_policy, -> { with_deleted }, optional: true
  # Which connector ingested this case (nil for portal/email/manual/API).
  belongs_to :source_connector, class_name: "Connector", optional: true
  belongs_to :routed_by_rule, class_name: "RoutingRule", optional: true
  belongs_to :merged_into, -> { with_deleted }, class_name: "Case", optional: true
  has_many :merged_cases, class_name: "Case", foreign_key: :merged_into_id, dependent: nil,
                          inverse_of: :merged_into

  has_many :messages, dependent: nil, inverse_of: :case
  has_many :audit_entries, as: :auditable, dependent: nil
  has_many :approval_requests, as: :subject, dependent: :destroy
  # Engineering work escalated from this case (WM4).
  has_many :work_links, as: :linkable, dependent: :destroy
  has_many :work_items, through: :work_links
  has_many :sla_clock_events, dependent: nil
  has_many :routing_rule_executions, dependent: nil
  has_one :csat_survey, dependent: nil
  has_many :case_presences, dependent: :destroy
  has_one :live_chat, dependent: :destroy
  has_many :call_records, dependent: nil
  has_many_attached :files
  include AttachableValidation

  before_validation :ensure_tracking_id, on: :create
  before_validation :stamp_status_changed_at
  before_validation :apply_default_sla_policy, on: :create
  before_save :compute_sla_due_dates, if: :sla_inputs_changed?
  after_create_commit :apply_routing_rules
  after_create_commit :enqueue_agent_triage
  after_create_commit :publish_created_webhook
  after_create_commit :notify_assignment, if: :assignee_id?
  after_update_commit :notify_assignment, if: :saved_change_to_assignee_id?
  after_create :start_sla_clocks
  after_update :record_sla_recalculation

  validates :subject, presence: true
  # DELIBERATELY not scoped to live rows (unlike every other uniqueness rule
  # here — see the W1 note on WorkflowState). A tracking ID is handed to a
  # customer; reissuing a deleted case's ID would show whoever still holds it
  # somebody else's case. The reservation is the point.
  validates :tracking_id, presence: true, uniqueness: { scope: :tenant_id }
  validate :status_changed_through_state_machine, on: :update
  # Only block ASSIGNING to an inactive user — a case keeps an assignee who
  # later goes inactive (unchanged assignee_id) so it stays editable.
  validate :assignee_must_be_active, if: -> { assignee_id.present? && will_save_change_to_assignee_id? }
  validate :merge_lineage_is_valid
  validates_same_tenant :merged_into

  scope :canonical, -> { where(merged_into_id: nil) }
  scope :open_cases, -> { canonical.where(status: OPEN_STATUSES) }
  # A breach is also real when the case left the open set (was resolved /
  # closed) after missing its deadline — otherwise a case resolved inside
  # the 5-minute sweep window after going overdue is never flagged (M18).
  scope :overdue_first_response, -> {
    base = canonical.where(first_response_breached: false).where.not(first_response_due_at: nil)
    still_open = base.where(first_responded_at: nil, status: OPEN_STATUSES)
                     .where("first_response_due_at < ?", Time.current)
    responded_late = base.where.not(first_responded_at: nil)
                         .where("first_responded_at > first_response_due_at")
    still_open.or(responded_late)
  }
  scope :overdue_resolution, -> {
    base = canonical.where(resolution_breached: false).where.not(resolution_due_at: nil)
    still_open = base.where(status: OPEN_STATUSES).where("resolution_due_at < ?", Time.current)
    resolved_late = base.where.not(resolved_at: nil).where("resolved_at > resolution_due_at")
    still_open.or(resolved_late)
  }
  scope :search, ->(q) {
    next all if q.blank?
    term = "%#{sanitize_sql_like(q.strip.downcase)}%"
    # external_id is in here deliberately: after a migration, the ticket ids in
    # a customer's inbox and an agent's muscle memory are the OLD system's.
    # Contact#external_id was already searchable; Case's was write-only, so
    # pasting "12345" on day one returned nothing.
    where("LOWER(cases.subject) LIKE :t ESCAPE '\\' OR LOWER(cases.tracking_id) LIKE :t ESCAPE '\\' " \
          "OR LOWER(cases.description) LIKE :t ESCAPE '\\' OR LOWER(cases.external_id) LIKE :t ESCAPE '\\'", t: term)
  }

  def self.generate_tracking_id
    segment = -> { Array.new(4) { TRACKING_ALPHABET[SecureRandom.random_number(TRACKING_ALPHABET.size)] }.join }
    "DKT-#{segment.call}-#{segment.call}"
  end

  def can_transition_to?(new_status)
    TRANSITIONS.fetch(status, []).include?(new_status.to_s)
  end

  def transition_to!(new_status)
    new_status = new_status.to_s
    return self if status == new_status

    unless can_transition_to?(new_status)
      raise InvalidTransition, "cannot transition case from #{status} to #{new_status}"
    end

    previous_status = status
    at = Time.current
    @transitioning = true
    transaction do
      self.status = new_status
      self.status_changed_at = at
      case new_status
      when "resolved"
        self.resolved_at = at
      when "closed"
        self.closed_at = at
      when "reopened"
        self.reopened_at = at
        self.reopen_count += 1
        self.resolved_at = nil
        self.closed_at = nil
      end
      save!
      SlaClock.transition!(self, from: previous_status, to: new_status, at: at)
    end
    publish_status_webhooks(previous_status)
    CsatSurvey.invite!(self) if status_resolved?
    self
  ensure
    @transitioning = false
  end

  def transition_to(new_status)
    transition_to!(new_status)
  rescue InvalidTransition, ActiveRecord::RecordInvalid
    false
  end

  def stamp_status_changed_at
    self.status_changed_at ||= Time.current
    self.status_changed_at = Time.current if will_save_change_to_status? && !will_save_change_to_status_changed_at?
  end

  # Maker-checker-aware transition (W3). If an ApprovalProcess guards this target
  # status and there's no fresh approval, park a pending request and return
  # false (the transition did NOT happen); otherwise transition and return true.
  # Used by every HUMAN- or model-initiated transition (controller + the
  # customer-reply auto-reopen) so the gate isn't bypassable off the controller
  # path. The approver's own apply calls transition_to! directly (no re-gate).
  def guarded_transition_to(new_status, requested_by: nil)
    if ApprovalGate.guarded_transition?(self, new_status) && !ApprovalGate.transition_cleared?(self, new_status)
      ApprovalGate.submit_transition!(self, new_status, requested_by: requested_by)
      return false
    end
    transition_to!(new_status)
    true
  end

  def open?
    OPEN_STATUSES.include?(status)
  end

  def canonical_record
    record = self
    seen = Set.new
    while record.merged_into && seen.add?(record.id)
      record = record.merged_into
    end
    record
  end

  def record_first_response!(at: Time.current)
    return if first_responded_at

    transaction do
      update!(first_responded_at: at)
      SlaClock.stop_first_response!(self, at: at) unless Imports::Mode.running?
    end
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
    self.sla_policy ||= Entitlement.policy_for(contact, at: created_at || Time.current)
    self.sla_policy ||= SlaPolicy.default
  end

  def sla_inputs_changed?
    new_record? || will_save_change_to_priority? || will_save_change_to_sla_policy_id?
  end

  def compute_sla_due_dates
    target = sla_policy&.target_for(priority)
    # A reopened conversation owns a fresh resolution clock. Changing its
    # priority must preserve that restart rather than silently moving the due
    # date back to the case's original creation time.
    base = reopened_at || created_at || Time.current
    if target.nil?
      self.first_response_due_at = nil unless first_responded_at
      self.resolution_due_at = nil unless resolved_at
      return
    end
    calendar = sla_policy&.business_calendar || BusinessCalendar.default
    if first_responded_at.nil?
      self.first_response_due_at = SlaClock.deadline(
        calendar: calendar, from: base, minutes: target.first_response_minutes
      )
    end
    if resolved_at.nil?
      if status_waiting_on_customer?
        self.resolution_remaining_minutes = target.resolution_minutes
        self.resolution_due_at = nil
      else
        self.resolution_due_at = SlaClock.deadline(
          calendar: calendar, from: base, minutes: target.resolution_minutes
        )
      end
    end
  end

  def start_sla_clocks
    return if Imports::Mode.running?

    SlaClock.start!(self)
  end

  def record_sla_recalculation
    return if Imports::Mode.running?
    return unless saved_change_to_priority? || saved_change_to_sla_policy_id?

    SlaClock.recalculate!(self, :first_response) unless first_responded_at
    SlaClock.recalculate!(self, :resolution) unless resolved_at
  end

  # Status mutations must come through #transition_to! — the single
  # state-machine location (handoff §2).
  def status_changed_through_state_machine
    return unless will_save_change_to_status?
    return if Imports::Mode.running?

    errors.add(:status, :must_use_state_machine) unless @transitioning
  end

  def assignee_must_be_active
    errors.add(:assignee, :inactive) unless assignee&.case_assignee?
  end

  def merge_lineage_is_valid
    return if merged_into.nil?

    errors.add(:merged_into, :same_case) if merged_into_id == id
    errors.add(:merged_into, :different_contact) if merged_into.contact_id != contact_id
    errors.add(:merged_into, :already_merged) if merged_into.merged_into_id.present?
  end

  # First-match declarative routing (CaseRouting) — deterministic, runs before
  # the AI triage and wins over it. No-op when no rule matches.
  def apply_routing_rules
    return if Imports::Mode.running?

    CaseRouting.apply(self)
  end

  # Customer-originated cases get the AI triage/draft/resolve loop when a model
  # endpoint is configured; silently nothing otherwise.
  def enqueue_agent_triage
    return if Imports::Mode.running?

    CaseAgentJob.perform_later(self) if ai_triage_eligible?
  end

  public

  # Whether the AI triage/draft/resolve loop will run for this case — used both
  # to enqueue it and (in CaseRouting) to decide whether a rule must complete
  # triage itself.
  def ai_triage_eligible?
    Llm.enabled? && (channel_web_portal? || channel_email? || channel_api?)
  end

  private

  def publish_created_webhook
    return if Imports::Mode.running?

    Webhooks.publish("case.created", Webhooks.case_payload(self))
  end

  def publish_status_webhooks(previous_status)
    payload = Webhooks.case_payload(self).merge(previous_status: previous_status)
    Webhooks.publish("case.status_changed", payload)
    Webhooks.publish("case.resolved", payload) if status_resolved?
  end

  def notify_assignment
    Notifications::Events.case_assigned(self)
  end
end
