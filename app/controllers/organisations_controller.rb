class OrganisationsController < ApplicationController
  before_action :set_organisation, only: %i[show edit update destroy]

  def index
    @pagy, @organisations = pagy(policy_scope(Organisation).order(:name))
  end

  def show
    authorize @organisation
    @pagy, @contacts = pagy(@organisation.contacts.order(:name))
    result = Customer360.new(
      subject: @organisation,
      case_scope: feature?("service_desk") && policy(Case).index? ? policy_scope(Case) : Case.none,
      deal_scope: feature?("crm") && policy(Deal).index? ? policy_scope(Deal) : Deal.none,
      work_scope: feature?("work") && policy(WorkItem).index? ? policy_scope(WorkItem) : WorkItem.none
    ).call
    @cases = result.cases
    @case_count = result.case_count
    @deals = result.deals
    @deal_count = result.deal_count
    @work_items = result.work_items
    @work_item_count = result.work_item_count
    @timeline = result.timeline
  end

  def new
    @organisation = Organisation.new
    authorize @organisation
  end

  def create
    @organisation = Organisation.new(organisation_params)
    authorize @organisation
    if @organisation.save
      redirect_to @organisation, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @organisation
  end

  def update
    authorize @organisation
    if @organisation.update(organisation_params)
      redirect_to @organisation, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @organisation
    @organisation.destroy
    redirect_to organisations_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_organisation
    @organisation = Organisation.find(params[:id])
  end

  def organisation_params
    params.require(:organisation).permit(:name, :kind, :external_ref, :notes)
  end
end
