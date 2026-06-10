module Admin
  class SettingsController < ApplicationController
    # Explicit allowlist: only these keys are writable from this form,
    # each with a coercion. BYOK enablement is deliberately a separate
    # checkbox carrying the egress warning (handoff §4).
    EDITABLE = {
      "llm_provider" => :string,
      "llm_endpoint_url" => :string,
      "llm_model" => :string,
      "llm_api_key" => :secret,
      "llm_byok_enabled" => :bool,
      "ai_draft_enabled" => :bool,
      "ai_route_confidence" => :float,
      "ai_resolve_confidence" => :float,
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

    def show
      authorize :settings, policy_class: AdminAreaPolicy
    end

    def update
      authorize :settings, policy_class: AdminAreaPolicy

      EDITABLE.each do |key, type|
        next unless params.key?(key)
        value = coerce(params[key], type)
        if value.nil?
          Setting.unset(key)
        else
          Setting.set(key, value)
        end
      end

      redirect_to admin_settings_path, notice: t(".updated")
    end

    private

    def coerce(raw, type)
      case type
      when :bool then raw == "1"
      when :int then raw.presence&.to_i
      when :float then raw.presence&.to_f
      when :secret then raw.presence # blank leaves unset; no echo back
      else raw.presence
      end
    end
  end
end
