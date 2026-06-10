class SsoFailuresController < ApplicationController
  allow_unauthenticated_access

  def show
    strategy = request.env["omniauth.error.strategy"]&.name.to_s
    destination = strategy == "customer_oidc" ? portal_root_path : new_session_path
    redirect_to destination, alert: t("sessions.sso_failed")
  end

  private

  def skip_pundit?
    true
  end
end
