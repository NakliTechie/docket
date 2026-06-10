class SlaPoliciesController < ApplicationController
  before_action :set_policy, only: %i[edit update destroy]

  def index
    @sla_policies = policy_scope(SlaPolicy).includes(:sla_targets).order(:name)
  end

  def new
    @sla_policy = SlaPolicy.new
    build_missing_targets
    authorize @sla_policy
  end

  def create
    @sla_policy = SlaPolicy.new(sla_policy_params)
    authorize @sla_policy
    if @sla_policy.save
      redirect_to sla_policies_path, notice: t(".created")
    else
      build_missing_targets
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @sla_policy
    build_missing_targets
  end

  def update
    authorize @sla_policy
    if @sla_policy.update(sla_policy_params)
      redirect_to sla_policies_path, notice: t(".updated")
    else
      build_missing_targets
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @sla_policy
    @sla_policy.destroy
    redirect_to sla_policies_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_policy
    @sla_policy = SlaPolicy.find(params[:id])
  end

  def build_missing_targets
    existing = @sla_policy.sla_targets.map(&:priority)
    (SlaTarget.priorities.keys - existing).each do |priority|
      @sla_policy.sla_targets.build(priority: priority)
    end
  end

  def sla_policy_params
    params.require(:sla_policy).permit(:name, :description,
      sla_targets_attributes: %i[id priority first_response_minutes resolution_minutes _destroy])
  end
end
