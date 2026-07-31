# Dual identity planes (handoff §5A), config in admin settings,
# env-overridable for compose deployments. Staff and customer planes
# never mix: staff auth lives in the signed :session_id cookie backed
# by Session rows; customer SSO lives in the Rails session cookie as
# :portal_contact_id. Each guard reads only its own plane.
module Sso
  module_function

  def setting(key, env_key)
    ENV[env_key].presence || Setting.get(key).presence
  end

  # OmniAuth's setup phase runs as Rack MIDDLEWARE — before TenantResolution
  # has put a tenant in scope. Settings resolve tenant-first with a global
  # fallback, so without this every per-tenant SSO setting is invisible to the
  # setup phase and the provider reports "not configured": SSO is dead for any
  # tenant that configured it on its own row rather than globally.
  #
  # Same fix, same reason, as Docket::Cors#allowed_origins — any middleware
  # that reads per-tenant Settings has to resolve the tenant from the host
  # itself. Unknown subdomain in a shared deploy → no tenant → the block runs
  # unscoped and the provider fails closed, which is correct.
  def with_request_tenant(env)
    tenant = Tenant.resolve_by_host(ActionDispatch::Request.new(env).host)
    return yield if tenant.nil?

    ActsAsTenant.with_tenant(tenant) { yield }
  end

  # -- staff OIDC --------------------------------------------------------

  def staff_oidc_enabled?
    staff_oidc_issuer.present? &&
      setting("sso_staff_oidc_client_id", "DOCKET_STAFF_OIDC_CLIENT_ID").present?
  end

  def staff_oidc_issuer
    setting("sso_staff_oidc_issuer", "DOCKET_STAFF_OIDC_ISSUER")
  end

  def staff_oidc_options
    issuer = staff_oidc_issuer
    {
      name: :staff_oidc,
      issuer: issuer,
      discovery: true,
      scope: [ :openid, :email, :profile ],
      response_type: :code,
      client_options: {
        identifier: setting("sso_staff_oidc_client_id", "DOCKET_STAFF_OIDC_CLIENT_ID"),
        secret: setting("sso_staff_oidc_client_secret", "DOCKET_STAFF_OIDC_CLIENT_SECRET"),
        redirect_uri: "#{base_url}/auth/staff_oidc/callback"
      }
    }
  end

  def staff_role_claim
    setting("sso_staff_role_claim", "DOCKET_STAFF_ROLE_CLAIM")
  end

  # JSON mapping of claim value → docket role, e.g.
  # {"docket-admins": "client_admin", "support-leads": "technical"}
  def staff_role_mapping
    raw = setting("sso_staff_role_mapping", "DOCKET_STAFF_ROLE_MAPPING")
    return {} if raw.blank?
    parsed = raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    # Valid-but-non-object JSON (e.g. "[1,2]" or "42") would later blow up
    # at mapping[value] — coerce anything that isn't a Hash to {}.
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  # JIT is deliberately opt-in by email domain. Existing users can keep using
  # SSO regardless of this list; it only controls who an IdP may create.
  def staff_jit_domains
    setting("sso_staff_jit_domains", "DOCKET_STAFF_JIT_DOMAINS")
      .to_s.split(/[\s,]+/).filter_map do |domain|
        normalized = domain.strip.downcase.delete_prefix("@")
        normalized if normalized.match?(/\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/)
      end.uniq
  end

  def staff_jit_allowed?(email)
    domain = email.to_s.downcase.split("@", 2).last
    domain.present? && staff_jit_domains.include?(domain)
  end

  # -- staff SAML --------------------------------------------------------

  def staff_saml_enabled?
    setting("sso_staff_saml_idp_sso_url", "DOCKET_STAFF_SAML_IDP_SSO_URL").present? &&
      setting("sso_staff_saml_idp_cert", "DOCKET_STAFF_SAML_IDP_CERT").present?
  end

  def staff_saml_options
    {
      name: :staff_saml,
      sp_entity_id: setting("sso_staff_saml_sp_entity_id", "DOCKET_STAFF_SAML_SP_ENTITY_ID") || "#{base_url}/auth/staff_saml/metadata",
      idp_sso_service_url: setting("sso_staff_saml_idp_sso_url", "DOCKET_STAFF_SAML_IDP_SSO_URL"),
      idp_cert: setting("sso_staff_saml_idp_cert", "DOCKET_STAFF_SAML_IDP_CERT"),
      assertion_consumer_service_url: "#{base_url}/auth/staff_saml/callback",
      name_identifier_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
    }
  end

  # -- customer OIDC -----------------------------------------------------

  def customer_oidc_enabled?
    setting("sso_customer_oidc_issuer", "DOCKET_CUSTOMER_OIDC_ISSUER").present? &&
      setting("sso_customer_oidc_client_id", "DOCKET_CUSTOMER_OIDC_CLIENT_ID").present?
  end

  def customer_oidc_options
    issuer = setting("sso_customer_oidc_issuer", "DOCKET_CUSTOMER_OIDC_ISSUER")
    {
      name: :customer_oidc,
      issuer: issuer,
      discovery: true,
      scope: [ :openid, :email, :profile ],
      response_type: :code,
      client_options: {
        identifier: setting("sso_customer_oidc_client_id", "DOCKET_CUSTOMER_OIDC_CLIENT_ID"),
        secret: setting("sso_customer_oidc_client_secret", "DOCKET_CUSTOMER_OIDC_CLIENT_SECRET"),
        redirect_uri: "#{base_url}/auth/customer_oidc/callback"
      }
    }
  end

  # Which claim carries the operator's customer identifier (CIF) that
  # maps to Contact.external_id. Default: the OIDC subject.
  def customer_external_id_claim
    setting("sso_customer_external_id_claim", "DOCKET_CUSTOMER_EXTERNAL_ID_CLAIM") || "sub"
  end

  def base_url
    Docket::TenantUrl.base_url
  end

  # Browsers enforce CSP form-action against the redirect target of a form
  # submission, so `form-action 'self'` alone silently kills the POST
  # /auth/* → IdP redirect of every SSO login. The configured IdP origins
  # must therefore be allowed alongside 'self'.
  def idp_form_action_origins
    urls = []
    urls << setting("sso_staff_oidc_issuer", "DOCKET_STAFF_OIDC_ISSUER") if staff_oidc_enabled?
    urls << setting("sso_customer_oidc_issuer", "DOCKET_CUSTOMER_OIDC_ISSUER") if customer_oidc_enabled?
    urls << setting("sso_staff_saml_idp_sso_url", "DOCKET_STAFF_SAML_IDP_SSO_URL") if staff_saml_enabled?
    urls.filter_map do |url|
      uri = URI.parse(url.to_s)
      next unless uri.is_a?(URI::HTTP) # covers https too
      origin = "#{uri.scheme}://#{uri.host}"
      origin += ":#{uri.port}" unless uri.port == uri.default_port
      origin
    rescue URI::InvalidURIError
      nil
    end.uniq
  end
end
