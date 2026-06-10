module Portal
  # Public, unauthenticated surface. Lives entirely outside the staff
  # session/policy world; rate-limited by Rack::Attack.
  class BaseController < ApplicationController
    allow_unauthenticated_access
    layout "portal"

    private

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
