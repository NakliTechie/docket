class ContactsController < ApplicationController
  before_action :set_contact, only: %i[show edit update destroy]

  def index
    @pagy, @contacts = pagy(policy_scope(Contact).includes(:organisation).search(params[:q]).order(:name))
  end

  def show
    authorize @contact
    @pagy, @cases = pagy(@contact.cases.includes(:queue, :assignee).order(created_at: :desc))
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
    if @contact.update(contact_update_params)
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

  def set_contact
    @contact = Contact.find(params[:id])
  end

  EDITABLE_ATTRS = %i[name email phone organisation_id preferred_language notes sms_consent].freeze

  def contact_params
    params.require(:contact).permit(*EDITABLE_ATTRS, :external_id)
  end

  # external_id is the SSO-linkage key: settable when first creating a
  # contact, but not rewritable through the edit form (would let staff
  # re-point a contact onto another customer's verified identity).
  def contact_update_params
    params.require(:contact).permit(*EDITABLE_ATTRS)
  end
end
