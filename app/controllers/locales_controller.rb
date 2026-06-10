class LocalesController < ApplicationController
  allow_unauthenticated_access

  def update
    locale = params[:locale].to_s
    if I18n.available_locales.map(&:to_s).include?(locale)
      session[:locale] = locale
      Current.user&.update(locale: locale)
    end
    redirect_back fallback_location: root_path
  end

  private

  def skip_pundit?
    true
  end
end
