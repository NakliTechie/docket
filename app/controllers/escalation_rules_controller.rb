# Admin CRUD for the SLA escalation matrix (PG3). Rules are position-ordered
# (like routing rules); each rule owns ordered levels edited inline via nested
# attributes. Blank level slots let admins add tiers; a slot with no
# after_minutes is dropped (reject_if), an existing tier is removed via _destroy.
class EscalationRulesController < ApplicationController
  require_feature "service_desk"
  before_action :set_rule, only: %i[edit update destroy move]

  BLANK_LEVEL_SLOTS = 3

  def index
    authorize EscalationRule
    @rules = policy_scope(EscalationRule).ordered
               .includes(escalation_levels: %i[then_assignee notify_user])
  end

  def new
    @rule = EscalationRule.new
    BLANK_LEVEL_SLOTS.times { @rule.escalation_levels.build }
    authorize @rule
  end

  def create
    @rule = EscalationRule.new(rule_params)
    @rule.position = next_position
    authorize @rule
    if @rule.save
      redirect_to escalation_rules_path, notice: t(".created")
    else
      pad_levels(@rule)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @rule
    pad_levels(@rule)
  end

  def update
    authorize @rule
    if @rule.update(rule_params)
      redirect_to escalation_rules_path, notice: t(".updated")
    else
      pad_levels(@rule)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @rule
    @rule.destroy
    redirect_to escalation_rules_path, notice: t(".deleted"), status: :see_other
  end

  # Swap this rule's position with its neighbour — evaluation precedence stays
  # explicit (rules are checked in position order).
  def move
    authorize @rule
    neighbour =
      if params[:dir] == "up"
        EscalationRule.where(active: @rule.active).where("position < ?", @rule.position).ordered.last
      else
        EscalationRule.where(active: @rule.active).where("position > ?", @rule.position).ordered.first
      end

    if neighbour
      EscalationRule.transaction do
        here, there = @rule.position, neighbour.position
        @rule.update_column(:position, there)
        neighbour.update_column(:position, here)
      end
    end
    redirect_to escalation_rules_path
  end

  private

  def set_rule
    @rule = EscalationRule.find(params[:id])
  end

  def next_position
    (EscalationRule.maximum(:position) || -1) + 1
  end

  # Keep a few empty level slots on the form for adding new tiers.
  def pad_levels(rule)
    blanks = BLANK_LEVEL_SLOTS - rule.escalation_levels.reject(&:persisted?).size
    blanks.clamp(0..).times { rule.escalation_levels.build }
  end

  def rule_params
    params.require(:escalation_rule).permit(
      :name, :active, :trigger_type, :breach_clock, :if_status, :if_priority,
      escalation_levels_attributes: %i[id after_minutes then_assignee_id notify_user_id _destroy]
    )
  end
end
