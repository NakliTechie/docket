module Portal
  # Public, unauthenticated surface. Lives entirely outside the staff
  # session/policy world; rate-limited by Rack::Attack.
  class BaseController < ApplicationController
    require_feature "service_desk.portal"
    allow_unauthenticated_access
    layout "portal"

    private

    def current_contact
      @current_contact ||= Contact.find_by(id: session[:portal_contact_id])
    end

    def require_customer
      redirect_to portal_root_path, alert: t("portal.customer.sign_in_required") if current_contact.nil?
    end

    # Only real multipart uploads — never a bare string. Without this a
    # customer (or anyone) could pass files: ["<active-storage-signed-id>"]
    # to attach an arbitrary existing blob by reference, or a garbage
    # string that 500s the request (M12). Mirrors the API's filter.
    def safe_files(raw)
      Array(raw).select { |f| f.respond_to?(:original_filename) }
    end

    def skip_pundit?
      true
    end

    def set_locale
      I18n.locale = session[:locale].presence || I18n.default_locale
    rescue I18n::InvalidLocale
      I18n.locale = I18n.default_locale
    end
  end
end
