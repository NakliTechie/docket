class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: :rate_limited

  def new
  end

  def create
    credentials = params.permit(:email_address, :password)
    # authenticate_by raises ArgumentError when either key is missing/blank
    # (e.g. a hand-crafted POST) — treat that as a failed login, not a 500.
    if credentials[:email_address].blank? || credentials[:password].blank?
      return failed_login(credentials[:email_address])
    end

    user = User.authenticate_by(credentials)
    if user&.active?
      start_new_session_for user
      AuditEntry.append!(action: "user.login", auditable: user, actor: user,
                         metadata: { ip: request.remote_ip })
      redirect_to after_authentication_url
    else
      failed_login(credentials[:email_address])
    end
  end

  def destroy
    user = Current.user
    terminate_session
    AuditEntry.append!(action: "user.logout", auditable: user, actor: user) if user
    redirect_to new_session_path, status: :see_other
  end

  private

  def failed_login(email)
    SecurityEvent.record("login_failed", email: email,
                         ip_address: request.remote_ip, user_agent: request.user_agent)
    redirect_to new_session_path, alert: t("sessions.invalid_credentials")
  end

  def rate_limited
    SecurityEvent.record("login_throttled", email: params[:email_address],
                         ip_address: request.remote_ip, user_agent: request.user_agent)
    redirect_to new_session_path, alert: t("sessions.rate_limited")
  end
end
