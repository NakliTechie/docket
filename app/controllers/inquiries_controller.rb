# Public, unauthenticated lead-capture form (v1.2 CRM) — a sales prospect
# "get in touch" form, separate from the case/support portal. Rate-limited by
# Rack::Attack. Lives outside the staff session/policy world.
class InquiriesController < ApplicationController
  require_feature "crm"
  allow_unauthenticated_access
  layout "public"

  def new
    @capture_form = capture_form
    @inquiry = LeadInquiry.new
  end

  def create
    # Honeypot: a hidden field real users never fill. If it's set, pretend
    # success without creating anything — give bots no signal.
    return render :confirmation, status: :created if params[:website].present?

    @capture_form = capture_form
    @inquiry = LeadInquiry.new(mapped_inquiry_params)
    if @inquiry.save
      render :confirmation, status: :created
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def skip_pundit?
    true
  end

  def set_locale
    I18n.locale = session[:locale].presence || I18n.default_locale
  rescue I18n::InvalidLocale
    I18n.locale = I18n.default_locale
  end

  def inquiry_params
    params.require(:lead_inquiry).permit(:name, :email, :phone, :company_name, :message,
                                         :email_consent, :sms_consent, fields: {})
  end

  def capture_form
    @capture_form ||= if params[:slug].present?
      LeadCaptureForm.active.find_by!(slug: params[:slug])
    else
      LeadCaptureForm.default_form
    end
  end

  def mapped_inquiry_params
    permitted = inquiry_params
    attributes = if @capture_form
      @capture_form.map_fields(permitted[:fields] || {})
    else
      permitted.slice(:name, :email, :phone, :company_name, :message).to_h
    end
    if @capture_form && attributes.key?("notes")
      attributes["message"] = attributes.delete("notes")
    end
    boolean = ActiveModel::Type::Boolean.new
    email_consent = !!boolean.cast(permitted[:email_consent])
    sms_consent = !!boolean.cast(permitted[:sms_consent])
    consented = email_consent || sms_consent
    attributes.merge(
      email_consent: email_consent, sms_consent: sms_consent,
      consent_captured_at: consented ? Time.current : nil,
      consent_source: @capture_form ? "web:#{@capture_form.slug}" : "web:inquiry",
      provenance: {
        "channel" => "web_form", "capture_form_id" => @capture_form&.id,
        "capture_form_slug" => @capture_form&.slug, "request_id" => request.request_id
      }.compact
    )
  end
end
