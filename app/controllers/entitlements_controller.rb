class EntitlementsController < ApplicationController
  require_feature "service_desk"
  before_action :set_entitlement, only: %i[edit update destroy]

  def index
    authorize Entitlement
    @entitlements = policy_scope(Entitlement)
      .includes(:contact, :organisation, :sla_policy).order(starts_at: :desc, name: :asc)
  end

  def new
    @entitlement = Entitlement.new(starts_at: Time.current.beginning_of_day)
    authorize @entitlement
  end

  def create
    @entitlement = Entitlement.new(entitlement_params)
    authorize @entitlement
    if @entitlement.save
      redirect_to entitlements_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @entitlement
  end

  def update
    authorize @entitlement
    if @entitlement.update(entitlement_params)
      redirect_to entitlements_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @entitlement
    @entitlement.destroy
    redirect_to entitlements_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_entitlement
    @entitlement = policy_scope(Entitlement).find(params[:id])
  end

  def entitlement_params
    params.require(:entitlement).permit(:name, :organisation_id, :contact_id,
                                        :sla_policy_id, :starts_at, :ends_at)
  end
end
