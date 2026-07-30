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

  def first_value?
    Case.exists? || Lead.exists? || Project.exists?
  end

  def completed_count
    [ brand_ready?, modules_confirmed?, intake_ready?, email_decided?,
      team_decided?, first_value? ].count(true)
  end

  def total_count = 6

  def portal_url
    "#{base_url}#{Rails.application.routes.url_helpers.portal_root_path}"
  end

  def active_modules
    CORE_MODULES.select { |key| Current.tenant&.feature?(key) }
  end

  def service_desk? = Current.tenant&.feature?("service_desk")
  def crm? = Current.tenant&.feature?("crm")
  def work? = Current.tenant&.feature?("work")
end
