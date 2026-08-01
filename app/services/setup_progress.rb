# The resumable first-run checklist. It derives real progress from tenant data
# wherever possible and uses explicit tenant settings only for choices that
# cannot be inferred ("these modules are right", "email/team can wait").
class SetupProgress
  CORE_MODULES = %w[service_desk crm work].freeze

  attr_reader :actor, :base_url

  def initialize(actor:, base_url:)
    @actor = actor
    @base_url = base_url.to_s.delete_suffix("/")
  end

  def fresh_tenant?
    Case.none? && Lead.none? && Project.none?
  end

  def started?
    Setting.get("setup_started") == true
  end

  def finished?
    Setting.get("setup_finished") == true
  end

  def needs_attention?
    fresh_tenant? || (started? && !finished?)
  end

  def mark_started!
    Setting.set("setup_started", true) unless started?
  end

  def finish!
    raise ArgumentError, "setup is not complete" unless complete?

    Setting.set("setup_finished", true)
  end

  def brand_ready?
    Setting.get("brand_name").present?
  end

  def modules_confirmed?
    Setting.get("setup_modules_confirmed") == true
  end

  def intake_ready?
    !service_desk? || (CaseQueue.exists? && SlaPolicy.exists?)
  end

  def email_configured?
    OutboundEmail.configured?
  end

  def email_decided?
    email_configured? || Setting.get("setup_email_skipped") == true
  end

  def team_ready?
    User.active.where.not(id: actor.id).exists?
  end

  def team_decided?
    team_ready? || Setting.get("setup_team_skipped") == true
  end

  def first_value_record
    @first_value_record ||= if service_desk?
      Case.canonical.order(:created_at, :id).first
    elsif crm?
      Lead.canonical.order(:created_at, :id).first
    elsif work?
      Project.order(:created_at, :id).first
    end
  end

  def first_value_kind
    return :service_desk if service_desk?
    return :crm if crm?
    return :work if work?

    :none
  end

  def first_record?
    first_value_record.present?
  end

  def first_value?
    record = first_value_record
    return false unless record

    if service_desk?
      service_desk_value?(record)
    elsif crm?
      record.status_converted?
    elsif work?
      record.work_items.closed.exists?
    else
      false
    end
  end

  def completed_count
    [ brand_ready?, modules_confirmed?, intake_ready?, email_decided?,
      team_decided?, first_value? ].count(true)
  end

  def total_count = 6

  def complete?
    completed_count == total_count
  end

  def portal_url
    "#{base_url}#{Rails.application.routes.url_helpers.portal_root_path}"
  end

  def active_modules
    CORE_MODULES.select { |key| Current.tenant&.feature?(key) }
  end

  def service_desk? = Current.tenant&.feature?("service_desk")
  def crm? = Current.tenant&.feature?("crm")
  def work? = Current.tenant&.feature?("work")

  private

  def service_desk_value?(kase)
    return false unless kase.assignee_id? && (kase.status_resolved? || kase.status_closed?)

    kase.messages.where(direction: :outbound, kind: %i[public_reply agent_turn])
        .where(author_type: %w[User ServiceAccount]).exists?
  end
end
