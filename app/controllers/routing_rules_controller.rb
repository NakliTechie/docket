# Admin CRUD for declarative routing rules (PG1). Rules are evaluated in
# `position` order on intake by CaseRouting — so ordering is first-class:
# new rules append to the end and #move swaps a rule with its neighbour.
class RoutingRulesController < ApplicationController
  before_action :set_rule, only: %i[edit update destroy move]

  def index
    authorize RoutingRule
    @rules = policy_scope(RoutingRule).ordered
               .includes(:match_category, :then_queue, :then_category, :then_assignee)
  end

  def new
    @rule = RoutingRule.new
    authorize @rule
  end

  def create
    @rule = RoutingRule.new(rule_params)
    @rule.position = next_position
    authorize @rule
    if @rule.save
      redirect_to routing_rules_path, notice: t(".created")
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
      redirect_to routing_rules_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @rule
    @rule.destroy
    redirect_to routing_rules_path, notice: t(".deleted"), status: :see_other
  end

  # Swap this rule's position with its neighbour in the requested direction —
  # the only way ordering changes, so evaluation precedence stays explicit.
  def move
    authorize @rule
    neighbour =
      if params[:dir] == "up"
        RoutingRule.where(active: @rule.active).where("position < ?", @rule.position).ordered.last
      else
        RoutingRule.where(active: @rule.active).where("position > ?", @rule.position).ordered.first
      end

    if neighbour
      RoutingRule.transaction do
        here, there = @rule.position, neighbour.position
        @rule.update_column(:position, there)
        neighbour.update_column(:position, here)
      end
    end
    redirect_to routing_rules_path
  end

  private

  def set_rule
    @rule = RoutingRule.find(params[:id])
  end

  def next_position
    (RoutingRule.maximum(:position) || -1) + 1
  end

  def rule_params
    params.require(:routing_rule).permit(
      :name, :active, :if_channel, :if_priority, :match_category_id, :if_subject_contains,
      :then_queue_id, :then_category_id, :then_priority, :then_assignment, :then_assignee_id
    )
  end
end
