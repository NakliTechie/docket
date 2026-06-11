# Public, unauthenticated lead-capture form (v1.2 CRM) — a sales prospect
# "get in touch" form, separate from the grievance portal. Rate-limited by
# Rack::Attack. Lives outside the staff session/policy world.
class InquiriesController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  def new
    @inquiry = LeadInquiry.new
  end

  def create
    # Honeypot: a hidden field real users never fill. If it's set, pretend
    # success without creating anything — give bots no signal.
    return render :confirmation, status: :created if params[:website].present?

    @inquiry = LeadInquiry.new(inquiry_params)
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
    params.require(:lead_inquiry).permit(:name, :email, :phone, :company_name, :message)
  end
end
