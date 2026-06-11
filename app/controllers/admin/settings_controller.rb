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
        raw = params[key]
        # Param-pollution guard: every editable setting is a scalar form
        # field. A Hash/Array here is a crafted request — ignore it
        # rather than letting coerce raise.
        next unless raw.nil? || raw.is_a?(String)

        # Secrets are write-only: the field is never echoed back, so a
        # blank submission means "leave the stored secret unchanged"
        # (otherwise every settings save would wipe all secrets, since
        # an empty password field always submits).
        next if type == :secret && raw.blank?

        value = coerce(raw, type, key)
        if value.nil?
          Setting.unset(key)
        else
          Setting.set(key, value)
        end
      end

      redirect_to admin_settings_path, notice: t(".updated")
    end

    private

    # Confidence thresholds are probabilities; clamp to [0, 1] so a
    # crafted or fat-fingered value can't disable/!invert the AI gates.
    CLAMPED_FLOATS = %w[ai_route_confidence ai_resolve_confidence].freeze

    def coerce(raw, type, key = nil)
      case type
      when :bool then raw == "1"
      when :int then raw.presence&.to_i
      when :float then clamp_float(raw, key)
      when :secret then raw.presence # blank handled by caller (leaves unchanged)
      else raw.presence
      end
    end

    def clamp_float(raw, key)
      f = raw.presence&.to_f
      return f unless f && CLAMPED_FLOATS.include?(key)
      f.clamp(0.0, 1.0)
    end
  end
end
