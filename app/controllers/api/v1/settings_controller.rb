module Api
  module V1
    class SettingsController < BaseController
      # What a secret reads back as — presence only, never the value.
      SECRET_MASK = "[SET]".freeze

      def show
        require_settings_access!("config:read")
        render json: { data: settings_payload }
      end

      def update
        require_settings_access!("config:write")
        SettingContract::EDITABLE.each do |key, type|
          next unless params.key?(key)
          raw = params[key]
          # Secrets are write-only: ignore a blank or the read mask so a
          # read-modify-write round-trip can neither wipe a stored secret
          # nor store the literal "[SET]" mask back over it.
          next if type == :secret && (raw.blank? || raw == SECRET_MASK)
          value = SettingContract.coerce(key, raw)
          next if SettingContract.invalid?(value)
          value.nil? ? Setting.unset(key) : Setting.set(key, value)
        end
        # Render directly — do NOT route through show, whose config:read gate
        # would 403 a config:write-only token after a successful write (M4).
        render json: { data: settings_payload }
      end

      private

      # Every :secret-typed key is masked — not just llm_api_key. The SSO client
      # secrets are secrets too and must never leave.
      def settings_payload
        SettingContract::EDITABLE.to_h do |key, type|
          value = Setting.get(key)
          value = (value.present? ? SECRET_MASK : nil) if type == :secret
          [ key, value ]
        end
      end

      def require_settings_access!(scope)
        if current_user
          raise Pundit::NotAuthorizedError unless current_user.can?("settings:manage")
        else
          raise ScopeDenied, scope unless current_access_token.scope?(scope)
        end
      end
    end
  end
end
