class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: t("sessions.rate_limited") }

  def new
  end

  def create
    user = User.authenticate_by(params.permit(:email_address, :password))
    if user&.active?
      start_new_session_for user
      AuditEntry.append!(action: "user.login", auditable: user, actor: user,
                         metadata: { ip: request.remote_ip })
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: t("sessions.invalid_credentials")
    end
  end

  def destroy
    user = Current.user
    terminate_session
    AuditEntry.append!(action: "user.logout", auditable: user, actor: user) if user
    redirect_to new_session_path, status: :see_other
  end
end
