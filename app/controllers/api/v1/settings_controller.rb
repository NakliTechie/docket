module Api
  module V1
    class SettingsController < BaseController
      # What a secret reads back as — presence only, never the value.
      SECRET_MASK = "[SET]".freeze

      def show
        require_settings_access!("config:read")
        # Every :secret-typed key is masked — not just llm_api_key. The
        # SSO client secrets are secrets too and must never leave.
        data = Admin::SettingsController::EDITABLE.to_h do |key, type|
          value = Setting.get(key)
          value = (value.present? ? SECRET_MASK : nil) if type == :secret
          [ key, value ]
        end
        render json: { data: data }
      end

      def update
        require_settings_access!("config:write")
        Admin::SettingsController::EDITABLE.each do |key, type|
          next unless params.key?(key)
          raw = params[key]
          # Secrets are write-only: ignore a blank or the read mask so a
          # read-modify-write round-trip can neither wipe a stored secret
          # nor store the literal "[SET]" mask back over it.
          next if type == :secret && (raw.blank? || raw == SECRET_MASK)
          value = coerce(raw, type)
          value.nil? ? Setting.unset(key) : Setting.set(key, value)
        end
        show
      end

      private

      def require_settings_access!(scope)
        if current_user
          raise Pundit::NotAuthorizedError unless current_user.role_admin?
        else
          raise ScopeDenied, scope unless current_access_token.scope?(scope)
        end
      end

      def coerce(raw, type)
        case type
        when :bool then ActiveModel::Type::Boolean.new.cast(raw)
        when :int then raw.presence&.to_i
        when :float then raw.presence&.to_f
        else raw.presence
        end
      end
    end
  end
end
