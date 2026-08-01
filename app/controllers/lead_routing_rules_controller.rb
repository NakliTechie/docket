# Admin CRUD for declarative lead-routing rules (PG1) — the lead-side mirror of
# RoutingRulesController. Rules are evaluated in position order on lead creation
# by LeadRouting, so ordering is first-class: new rules append; #move swaps a
# rule with its neighbour.
class LeadRoutingRulesController < ApplicationController
  require_feature "crm"
  before_action :set_rule, only: %i[edit update destroy move]

  def index
    authorize LeadRoutingRule
    @rules = policy_scope(LeadRoutingRule).ordered.includes(:then_owner)
  end

  def new
    @rule = LeadRoutingRule.new
    authorize @rule
  end

  def create
    @rule = LeadRoutingRule.new(rule_params)
    @rule.position = next_position
    authorize @rule
    if @rule.save
      redirect_to lead_routing_rules_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @rule
  end

  def update
    authorize @rule
    if @rule.update(rule_params)
      redirect_to lead_routing_rules_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @rule
    @rule.destroy
    redirect_to lead_routing_rules_path, notice: t(".deleted"), status: :see_other
  end

  # Swap this rule's position with its neighbour in the requested direction —
  # the only way ordering changes, so evaluation precedence stays explicit.
  def move
    authorize @rule
    neighbour =
      if params[:dir] == "up"
        LeadRoutingRule.where(active: @rule.active).where("position < ?", @rule.position).ordered.last
      else
        LeadRoutingRule.where(active: @rule.active).where("position > ?", @rule.position).ordered.first
      end

    if neighbour
      LeadRoutingRule.transaction do
        here, there = @rule.position, neighbour.position
        @rule.update_column(:position, there)
        neighbour.update_column(:position, here)
      end
    end
    redirect_to lead_routing_rules_path
  end

  private

  def set_rule
    @rule = LeadRoutingRule.find(params[:id])
  end

  def next_position
    (LeadRoutingRule.maximum(:position) || -1) + 1
  end

  def rule_params
    params.require(:lead_routing_rule).permit(
      :name, :active, :if_source, :if_company_contains, :if_email_domain,
      :then_assignment, :then_owner_id
    )
  end
end
