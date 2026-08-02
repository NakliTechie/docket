class ContactsController < ApplicationController
  before_action :set_contact, only: %i[show edit update destroy]

  def index
    @pagy, @contacts = pagy(policy_scope(Contact).includes(:organisation).search(params[:q]).order(:name))
  end

  def show
    authorize @contact
    result = Customer360.new(
      subject: @contact,
      case_scope: feature?("service_desk") && policy(Case).index? ? policy_scope(Case) : Case.none,
      deal_scope: feature?("crm") && policy(Deal).index? ? policy_scope(Deal) : Deal.none,
      work_scope: feature?("work") && policy(WorkItem).index? ? policy_scope(WorkItem) : WorkItem.none,
      activity_scope: feature?("crm") && policy(Activity).index? ? policy_scope(Activity) : Activity.none
    ).call
    assign_customer_360(result)
    if feature?("crm")
      case_scope = feature?("service_desk") && policy(Case).index? ? policy_scope(Case) : Case.none
      visible_types = [ "Contact" ]
      visible_types << "Lead" if policy(Lead).index?
      visible_types << "Deal" if policy(Deal).index?
      @conversation = CrmConversation.call(@contact, case_scope: case_scope, visible_types: visible_types)
      @crm_bcc_address = CrmMailboxAddress.address_for(@contact)
    end
  end

  def new
    @contact = Contact.new
    authorize @contact
  end

  def create
    @contact = Contact.new(contact_params)
    authorize @contact
    if @contact.save
      redirect_to @contact, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @contact
  end

  def update
    authorize @contact
    attributes = contact_update_params
    custom_fields = attributes.delete(:custom_fields)
    @contact.assign_attributes(attributes)
    @contact.assign_custom_fields(custom_fields) if custom_fields
    if @contact.save
      redirect_to @contact, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @contact
    if @contact.destroy
      redirect_to contacts_path, notice: t(".deleted"), status: :see_other
    else
      redirect_to @contact, alert: @contact.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def assign_customer_360(result)
    @cases = result.cases
    @case_count = result.case_count
    @deals = result.deals
    @deal_count = result.deal_count
    @work_items = result.work_items
    @work_item_count = result.work_item_count
    @timeline = result.timeline
  end

  def set_contact
    @contact = Contact.find(params[:id])
  end

  EDITABLE_ATTRS = %i[
    name email phone job_title whatsapp_handle telegram_handle organisation_id preferred_language
    notes sms_consent email_consent
  ].freeze

  def contact_params
    params.require(:contact).permit(*EDITABLE_ATTRS, :external_id, custom_fields: {})
  end

  # external_id is the SSO-linkage key: settable when first creating a
  # contact, but not rewritable through the edit form (would let staff
  # re-point a contact onto another customer's verified identity).
  def contact_update_params
    params.require(:contact).permit(*EDITABLE_ATTRS, custom_fields: {})
  end
end
