# Staff SSO callbacks (OIDC + SAML). JIT-provisions users on first
# login with the least-privilege default role; an admin promotes, or a
# configured IdP role claim maps roles automatically. Local password auth
# remains as break-glass.
class SsoSessionsController < ApplicationController
  allow_unauthenticated_access only: :create
  skip_before_action :verify_authenticity_token, only: :create

  # Demotion-safety rank: the highest mapped group wins when an IdP asserts
  # several. The functional roles below client_admin are siblings, not a strict
  # lattice — finance/technical rank above sales/customer_service so a conflict
  # errs toward the more-privileged. Legacy roles retained until they're
  # migrated out. Every User.roles key MUST appear here (asserted in test) or
  # an SSO-asserted role is mis-ranked or unassignable.
  ROLE_RANK = {
    "super_admin" => 6, "client_admin" => 5, "finance" => 4, "technical" => 3,
    "sales" => 2, "customer_service" => 1, "readonly" => 0,
    "admin" => 6, "supervisor" => 5, "agent" => 1 # legacy
  }.freeze
  DEFAULT_SSO_ROLE = "customer_service".freeze

  def create
    auth = request.env["omniauth.auth"]
    email = auth&.info&.email.to_s.strip.downcase
    # Don't link/provision by an email the IdP says it hasn't verified —
    # otherwise an account on an IdP with unverified emails could assert a
    # victim's address (M6). Absent claim (e.g. SAML) is allowed; only an
    # explicit false is rejected.
    if email.blank? || email_unverified?(auth)
      SecurityEvent.record("sso_rejected", email: email, ip_address: request.remote_ip,
                           user_agent: request.user_agent, metadata: { provider: auth&.provider })
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
      role: DEFAULT_SSO_ROLE
    )
  end

  def email_unverified?(auth)
    verified = auth.extra&.raw_info&.[]("email_verified")
    verified = auth.info&.[]("email_verified") if verified.nil?
    verified == false || verified.to_s == "false"
  end

  # Role mapping from an IdP claim/attribute is configurable (§5A). When
  # it's set the IdP is authoritative: the HIGHEST mapped group wins (M8),
  # and a user with no mapped group is demoted to the default rather than
  # keeping a stale (possibly admin) role (M7). The claim may be a string
  # or array.
  def apply_role_mapping(user, auth)
    claim = Sso.staff_role_claim
    mapping = Sso.staff_role_mapping
    return if claim.blank? || mapping.blank?

    values = Array(auth.extra&.raw_info&.[](claim) || auth.info&.[](claim)).flatten.map(&:to_s)
    mapped = values.filter_map { |v| mapping[v] }
                   .select { |r| User.roles.key?(r) }
                   .max_by { |r| ROLE_RANK.fetch(r, -1) }
    target = mapped || DEFAULT_SSO_ROLE
    user.update!(role: target) if user.role != target
  end
end
