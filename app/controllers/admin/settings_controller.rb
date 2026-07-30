module Admin
  class SettingsController < ApplicationController
    # Explicit allowlist: only these keys are writable from this form,
    # each with a coercion. BYOK enablement is deliberately a separate
    # checkbox carrying the egress warning (handoff §4).
    EDITABLE = SettingContract::EDITABLE

    def show
      authorize :settings, policy_class: PlatformAreaPolicy
    end

    def update
      authorize :settings, policy_class: PlatformAreaPolicy

      EDITABLE.each do |key, type|
        next unless params.key?(key)
        raw = params[key]
        # Secrets are write-only: the field is never echoed back, so a
        # blank submission means "leave the stored secret unchanged"
        # (otherwise every settings save would wipe all secrets, since
        # an empty password field always submits).
        next if type == :secret && raw.blank?

        value = SettingContract.coerce(key, raw)
        next if SettingContract.invalid?(value)
        if value.nil?
          Setting.unset(key)
        else
          Setting.set(key, value)
        end
      end

      redirect_to admin_settings_path, notice: t(".updated")
    end
  end
end
