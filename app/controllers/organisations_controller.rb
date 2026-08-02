class OrganisationsController < ApplicationController
  before_action :set_organisation, only: %i[show edit update destroy]

  def index
    @pagy, @organisations = pagy(policy_scope(Organisation).order(:name))
  end

  def show
    authorize @organisation
    visible_organisations = policy_scope(Organisation)
    @parent = visible_organisations.find_by(id: @organisation.parent_id)
    @children = visible_organisations.where(parent: @organisation).order(:name)
    @pagy, @contacts = pagy(policy_scope(Contact).where(organisation: @organisation).order(:name))
    result = Customer360.new(
      subject: @organisation,
      case_scope: feature?("service_desk") && policy(Case).index? ? policy_scope(Case) : Case.none,
      deal_scope: feature?("crm") && policy(Deal).index? ? policy_scope(Deal) : Deal.none,
      work_scope: feature?("work") && policy(WorkItem).index? ? policy_scope(WorkItem) : WorkItem.none,
      activity_scope: feature?("crm") && policy(Activity).index? ? policy_scope(Activity) : Activity.none,
      sequence_delivery_scope: sequence_delivery_scope
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
    @organisation = Organisation.new(owner: Current.user)
    authorize @organisation
  end

  def create
    @organisation = Organisation.new(organisation_params)
    @organisation.owner ||= Current.user
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

  def sequence_delivery_scope
    return SequenceDelivery.none unless feature?("crm.sequences") && policy(Sequence).index?

    SequenceDelivery.all
  end

  def set_organisation
    @organisation = Organisation.find(params[:id])
  end

  def organisation_params
    params.require(:organisation).permit(:name, :kind, :external_ref, :notes, :parent_id, :owner_id)
  end
end
