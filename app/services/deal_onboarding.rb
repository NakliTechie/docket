class DealOnboarding
  Error = Class.new(StandardError)

  def self.call(...) = new(...).call

  def initialize(deal:, template:, actor:)
    @deal = deal
    @template = template
    @actor = actor
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
    raise Error, "only a won deal can start onboarding" unless @deal.status_won?
    raise Error, "template is inactive" unless @template.active?
    raise Error, "deal and template must belong to the same tenant" if @deal.tenant_id != @template.tenant_id
    unless @deal.tenant.feature?("crm") && @deal.tenant.feature?("work")
      raise Error, "CRM and Work must both be enabled"
    end
  end

  def create_project
    project = Project.create!(
      key: next_key, name: "Onboarding — #{@deal.name}", description: @template.description,
      lead: @deal.owner, onboarding_deal: @deal, project_template: @template
    )
    @template.project_template_items.each do |template_item|
      item = project.work_items.create!(
        title: template_item.title, description: template_item.description,
        kind: template_item.kind, priority: template_item.priority,
        estimate: template_item.estimate,
        due_on: template_item.due_offset_days && Date.current + template_item.due_offset_days,
        reporter: @actor.is_a?(User) ? @actor : nil
      )
      item.work_links.create!(linkable: @deal, relation: :onboarding_for,
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
