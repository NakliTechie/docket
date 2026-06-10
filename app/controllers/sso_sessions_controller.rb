# Staff SSO callbacks (OIDC + SAML). JIT-provisions users on first
# login with default role `agent`; an admin promotes, or a configured
# IdP role claim maps roles automatically. Local password auth remains
# as break-glass.
class SsoSessionsController < ApplicationController
  allow_unauthenticated_access only: :create
  skip_before_action :verify_authenticity_token, only: :create

  def create
    auth = request.env["omniauth.auth"]
    email = auth&.info&.email.to_s.strip.downcase
    if email.blank?
      return redirect_to new_session_path, alert: t("sessions.sso_failed")
    end

    user = User.find_by(email_address: email) || jit_provision(email, auth)
    apply_role_mapping(user, auth)

    if user.active?
      start_new_session_for user
      AuditEntry.append!(action: "user.login_sso", auditable: user, actor: user,
                         metadata: { ip: request.remote_ip, provider: auth.provider })
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: t("sessions.invalid_credentials")
    end
  end

  private

  def skip_pundit?
    true
  end

  def jit_provision(email, auth)
    User.create!(
      name: auth.info.name.presence || email.split("@").first,
      email_address: email,
      password: SecureRandom.hex(24),
      role: :agent
    )
  end

  # Role mapping from an IdP claim/attribute is configurable (§5A):
  # the claim may be a string or array; first mapped value wins.
  def apply_role_mapping(user, auth)
    claim = Sso.staff_role_claim
    mapping = Sso.staff_role_mapping
    return if claim.blank? || mapping.blank?

    values = Array(auth.extra&.raw_info&.[](claim) || auth.info&.[](claim)).flatten.map(&:to_s)
    mapped = values.filter_map { |v| mapping[v] }.first
    user.update!(role: mapped) if mapped.present? && User.roles.key?(mapped) && user.role != mapped
  end
end
