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

  # -- staff OIDC --------------------------------------------------------

  def staff_oidc_enabled?
    setting("sso_staff_oidc_issuer", "DOCKET_STAFF_OIDC_ISSUER").present? &&
      setting("sso_staff_oidc_client_id", "DOCKET_STAFF_OIDC_CLIENT_ID").present?
  end

  def staff_oidc_options
    issuer = setting("sso_staff_oidc_issuer", "DOCKET_STAFF_OIDC_ISSUER")
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
  # {"docket-admins": "admin", "grievance-supervisors": "supervisor"}
  def staff_role_mapping
    raw = setting("sso_staff_role_mapping", "DOCKET_STAFF_ROLE_MAPPING")
    return {} if raw.blank?
    raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
  rescue JSON::ParserError
    {}
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
    {
      name: :customer_oidc,
      issuer: setting("sso_customer_oidc_issuer", "DOCKET_CUSTOMER_OIDC_ISSUER"),
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
    setting("app_base_url", "DOCKET_BASE_URL") || "http://localhost:3000"
  end
end
