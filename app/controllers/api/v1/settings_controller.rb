module Api
  module V1
    class SettingsController < BaseController
      def show
        require_settings_access!("config:read")
        data = Admin::SettingsController::EDITABLE.keys.index_with { |key| Setting.get(key) }
        # Secrets never leave, even to admins — presence only.
        data["llm_api_key"] = Setting.get("llm_api_key").present? ? "[SET]" : nil
        render json: { data: data }
      end

      def update
        require_settings_access!("config:write")
        Admin::SettingsController::EDITABLE.each do |key, type|
          next unless params.key?(key)
          value = coerce(params[key], type)
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
