class LeadCaptureFormsController < ApplicationController
  require_feature "crm"
  before_action :set_form, only: %i[edit update destroy]

  def index
    authorize LeadCaptureForm
    @forms = policy_scope(LeadCaptureForm).order(:name)
  end

  def new
    @form = LeadCaptureForm.new(field_mapping: LeadCaptureForm::DEFAULT_MAPPING)
    authorize @form
  end

  def create
    @form = LeadCaptureForm.new(form_attributes)
    authorize @form
    if @form.save
      redirect_to lead_capture_forms_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @form
  end

  def update
    authorize @form
    if @form.update(form_attributes)
      redirect_to lead_capture_forms_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @form
    @form.destroy
    redirect_to lead_capture_forms_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_form
    @form = policy_scope(LeadCaptureForm).find(params[:id])
  end

  def form_attributes
    base = params.require(:lead_capture_form).permit(:name, :slug, :consent_disclosure,
                                                     :active, :is_default, :campaign_id)
    source_names = params.fetch(:mapping, {}).permit(*LeadCaptureForm::TARGET_FIELDS).to_h
    base[:field_mapping] = source_names.each_with_object({}) do |(target, source), mapping|
      mapping[source.to_s.strip] = target if source.present?
    end
    base
  end
end
