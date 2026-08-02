class LeadsController < ApplicationController
  require_feature "crm"
  before_action :set_lead, only: %i[show edit update destroy convert mark_unqualified merge]

  def index
    scope = policy_scope(Lead).canonical.includes(:owner, :contact).search(params[:q])
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
    scope = params[:sort] == "score" ? scope.by_score : scope.order(created_at: :desc)
    @pagy, @leads = pagy(scope)
  end

  def show
    authorize @lead
    @duplicate_leads = LeadDuplicateFinder.call(@lead).order(created_at: :desc)
    case_scope = feature?("service_desk") && policy(Case).index? ? policy_scope(Case) : Case.none
    visible_types = [ "Lead" ]
    visible_types << "Contact" if policy(Contact).index?
    visible_types << "Deal" if policy(Deal).index?
    @conversation = CrmConversation.call(
      @lead, case_scope: case_scope,
      contact_scope: policy(Contact).index? ? policy_scope(Contact) : Contact.none,
      lead_scope: policy_scope(Lead),
      deal_scope: policy(Deal).index? ? policy_scope(Deal) : Deal.none,
      visible_types: visible_types
    )
    @crm_bcc_address = CrmMailboxAddress.address_for(@lead)
  end

  def new
    @lead = Lead.new(owner: Current.user)
    authorize @lead
  end

  def create
    @lead = Lead.new(lead_params)
    @lead.owner ||= Current.user
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
    attributes = lead_params
    custom_fields = attributes.delete(:custom_fields)
    @lead.assign_attributes(attributes)
    @lead.assign_custom_fields(custom_fields) if custom_fields
    if @lead.save
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

  def merge
    authorize @lead
    source = policy_scope(Lead).canonical.find(params.require(:source_lead_id))
    authorize source, :merge?
    LeadMerge.call(source: source, target: @lead, actor: Current.user)
    redirect_to lead_path(@lead), notice: t(".merged", name: source.name)
  rescue LeadMerge::Error => error
    redirect_to lead_path(@lead), alert: error.message, status: :see_other
  end

  private

  def set_lead
    @lead = Lead.find(params[:id]).canonical_record
  end

  def lead_params
    params.require(:lead).permit(:name, :email, :phone, :company_name, :job_title,
                                 :whatsapp_handle, :telegram_handle,
                                 :source, :owner_id, :value_estimate, :notes,
                                 :sms_consent, :email_consent, :first_touch_campaign_id,
                                 custom_fields: {})
  end
end
