module Portal
  # Public, unauthenticated surface. Lives entirely outside the staff
  # session/policy world; rate-limited by Rack::Attack.
  class BaseController < ApplicationController
    allow_unauthenticated_access
    layout "portal"

    private

    # Only real multipart uploads — never a bare string. Without this a
    # citizen (or anyone) could pass files: ["<active-storage-signed-id>"]
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
