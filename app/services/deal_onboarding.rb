class DealOnboarding
  Error = Class.new(StandardError)

  # Two modes over the same machinery. :onboarding (default, unchanged) spins a
  # delivery project from a WON deal. :engagement spins a project from an OPEN
  # deal so pre-quote studies (WorkItems) can run before the quote exists. Both
  # link the project to the deal via onboarding_deal, so a deal has one project
  # (studies now, delivery later on the same project) — the unique index holds.
  MODES = {
    onboarding: { name_prefix: "Onboarding", project_kind: :onboarding, relation: :onboarding_for,
                  allowed: ->(deal) { deal.status_won? },
                  denied_message: "only a won deal can start onboarding" },
    engagement: { name_prefix: "Engagement", project_kind: :engagement, relation: :study_for,
                  allowed: ->(deal) { deal.status_open? },
                  denied_message: "an engagement can only start on an open deal" }
  }.freeze

  def self.call(...) = new(...).call

  def initialize(deal:, template:, actor:, mode: :onboarding)
    @deal = deal
    @template = template
    @actor = actor
    @mode = MODES.fetch(mode) { raise Error, "unknown onboarding mode #{mode.inspect}" }
  end

  def call
    validate!
    existing = Project.find_by(onboarding_deal: @deal)
    return existing if existing

    Project.transaction do
      @deal.lock!
      @template.lock!
      Project.find_by(onboarding_deal: @deal) || create_project
    end
  rescue ActiveRecord::RecordNotUnique
    Project.find_by!(onboarding_deal: @deal)
  end

  private

  def validate!
    raise Error, @mode[:denied_message] unless @mode[:allowed].call(@deal)
    raise Error, "template is inactive" unless @template.active?
    raise Error, "deal and template must belong to the same tenant" if @deal.tenant_id != @template.tenant_id
    unless @deal.tenant.feature?("crm") && @deal.tenant.feature?("work")
      raise Error, "CRM and Work must both be enabled"
    end
  end

  def create_project
    project = Project.create!(
      key: next_key, name: "#{@mode[:name_prefix]} — #{@deal.name}", description: @template.description,
      lead: @deal.owner, onboarding_deal: @deal, project_template: @template, kind: @mode[:project_kind]
    )
    @template.project_template_items.each do |template_item|
      item = project.work_items.create!(
        title: template_item.title, description: template_item.description,
        kind: template_item.kind, priority: template_item.priority,
        estimate: template_item.estimate,
        due_on: template_item.due_offset_days && Date.current + template_item.due_offset_days,
        reporter: @actor.is_a?(User) ? @actor : nil
      )
      item.work_links.create!(linkable: @deal, relation: @mode[:relation],
                              created_by: @actor.is_a?(User) ? @actor : nil)
    end
    project
  end

  def next_key
    prefix = @template.key_prefix
    return prefix unless Project.with_deleted.exists?(key: prefix)

    2.upto(999) do |number|
      suffix = number.to_s
      candidate = "#{prefix.first(10 - suffix.length)}#{suffix}"
      return candidate unless Project.with_deleted.exists?(key: candidate)
    end
    raise Error, "no project key is available for this template"
  end
end
