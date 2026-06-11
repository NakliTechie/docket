class LeadsController < ApplicationController
  before_action :set_lead, only: %i[show edit update destroy convert mark_unqualified]

  def index
    scope = policy_scope(Lead).includes(:owner, :contact).search(params[:q])
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    @pagy, @leads = pagy(scope.order(created_at: :desc))
  end

  def show
    authorize @lead
  end

  def new
    @lead = Lead.new
    authorize @lead
  end

  def create
    @lead = Lead.new(lead_params)
    authorize @lead
    if @lead.save
      redirect_to @lead, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @lead
  end

  def update
    authorize @lead
    if @lead.update(lead_params)
      redirect_to @lead, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @lead
    @lead.destroy
    redirect_to leads_path, notice: t(".deleted"), status: :see_other
  end

  def convert
    authorize @lead, :convert?
    contact = @lead.convert!
    redirect_to contact_path(contact), notice: t(".converted")
  end

  def mark_unqualified
    authorize @lead, :mark_unqualified?
    @lead.mark_unqualified!
    redirect_to @lead, notice: t(".unqualified")
  end

  private

  def set_lead
    @lead = Lead.find(params[:id])
  end

  def lead_params
    params.require(:lead).permit(:name, :email, :phone, :company_name,
                                 :source, :owner_id, :value_estimate, :notes)
  end
end
