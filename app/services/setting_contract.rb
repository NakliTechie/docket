# One typed contract for deployment settings, shared by the HTML console and
# REST API. It owns input-shape validation and probability clamping so the two
# surfaces cannot silently acquire different safety semantics.
module SettingContract
  INVALID = Object.new.freeze

  EDITABLE = {
    "brand_name" => :string,
    "llm_provider" => :string,
    "llm_endpoint_url" => :string,
    "llm_model" => :string,
    "llm_api_key" => :secret,
    "llm_byok_enabled" => :bool,
    "ai_draft_enabled" => :bool,
    "ai_route_confidence" => :float,
    "ai_resolve_confidence" => :float,
    "effector_agent_id" => :int,
    "default_queue_id" => :int,
    "default_sla_policy_id" => :int,
    "outbound_email_from" => :string,
    "cors_allowed_origins" => :string,
    "app_base_url" => :string,
    "sso_staff_oidc_issuer" => :string,
    "sso_staff_oidc_client_id" => :string,
    "sso_staff_oidc_client_secret" => :secret,
    "sso_staff_role_claim" => :string,
    "sso_staff_role_mapping" => :string,
    "sso_staff_saml_idp_sso_url" => :string,
    "sso_staff_saml_idp_cert" => :string,
    "sso_staff_saml_sp_entity_id" => :string,
    "sso_customer_oidc_issuer" => :string,
    "sso_customer_oidc_client_id" => :string,
    "sso_customer_oidc_client_secret" => :secret,
    "sso_customer_external_id_claim" => :string
  }.freeze

  BOOLEAN_VALUES = [ true, false, 0, 1, "0", "1", "true", "false", "on", "off" ].freeze

  module_function

  def coerce(key, raw)
    type = EDITABLE.fetch(key.to_s)
    return INVALID unless valid_shape?(raw, type)
    return nil if raw.nil? || (raw.is_a?(String) && raw.blank?)

    value = case type
    when :bool
      ActiveModel::Type::Boolean.new.cast(raw)
    when :int
      raw.is_a?(Numeric) ? raw.to_i : Integer(raw, exception: false)
    when :float
      raw.is_a?(Numeric) ? raw.to_f : Float(raw, exception: false)
    else
      raw.presence
    end
    return INVALID if value.nil? && raw.present?

    Setting::PROBABILITY_KEYS.include?(key.to_s) ? value.clamp(0.0, 1.0) : value
  end

  def invalid?(value)
    value.equal?(INVALID)
  end

  def valid_shape?(raw, type)
    return true if raw.nil?

    case type
    when :bool then BOOLEAN_VALUES.include?(raw)
    when :int, :float then raw.is_a?(String) || raw.is_a?(Numeric)
    else raw.is_a?(String)
    end
  end
  private_class_method :valid_shape?
end
