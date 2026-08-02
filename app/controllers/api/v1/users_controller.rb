module Api
  module V1
    # Identity management is human-only: no service-account scope opens
    # user records (privilege-escalation guard).
    class UsersController < BaseController
      before_action :require_human!
      before_action :set_user, only: %i[show update]

      def index
        authorize User
        pagy, records = pagy(policy_scope(User).order(:name))
        render json: { data: records.map { |u| Serialize.user(u) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize @user
        render json: { data: Serialize.user(@user) }
      end

      def create
        authorize User
        user = User.new(user_params.except(:record_read_scope, :record_write_scope,
                                           :team_ids, :scoped_account_ids))
        role_valid = assign_requested_role(user)
        scope_valid = assign_requested_record_scopes(user)
        if role_valid && scope_valid && save_with_scope_memberships(user)
          render json: { data: Serialize.user(user) }, status: :created
        else
          render_validation_errors(user)
        end
      end

      def update
        authorize @user
        if scope_assignment_requested? && !policy(@user).update_scope?
          @user.errors.add(:base, :scope_self_managed)
          return render_validation_errors(@user)
        end
        attrs = user_params
        attrs = attrs.except(:password) if attrs[:password].blank?
        attrs = attrs.except(:record_read_scope, :record_write_scope,
                             :team_ids, :scoped_account_ids)
        @user.assign_attributes(attrs)
        role_valid = assign_requested_role(@user)
        scope_valid = assign_requested_record_scopes(@user)
        if role_valid && scope_valid && save_with_scope_memberships(@user)
          render json: { data: Serialize.user(@user) }
        else
          render_validation_errors(@user)
        end
      end

      private

      def require_human!
        raise ScopeDenied, "human-only" unless current_user
      end

      def set_user
        @user = User.find(params[:id])
      end

      def user_params
        params.require(:user).permit(:name, :email_address, :password, :locale,
                                     :active, :email_signature, :record_read_scope,
                                     :record_write_scope, queue_ids: [], team_ids: [],
                                     scoped_account_ids: [])
      end

      def assign_requested_role(user)
        return true unless params.require(:user).key?(:role)

        role = params.require(:user)[:role]
        if role.is_a?(String) && User.roles.key?(role)
          user.role = role
          true
        else
          user.errors.add(:role, :inclusion)
          false
        end
      end

      def assign_requested_record_scopes(user)
        raw = params.require(:user)
        %i[record_read_scope record_write_scope].all? do |attribute|
          next true unless raw.key?(attribute)

          value = raw[attribute]
          allowed = User.public_send(attribute.to_s.pluralize)
          if value.is_a?(String) && allowed.key?(value)
            user.public_send("#{attribute}=", value)
            true
          else
            user.errors.add(attribute, :inclusion)
            false
          end
        end
      end

      def scope_assignment_requested?
        raw = params.require(:user)
        %i[record_read_scope record_write_scope team_ids scoped_account_ids].any? { |key| raw.key?(key) }
      end

      def save_with_scope_memberships(user)
        saved = false
        User.transaction do
          saved = user.save
          if saved
            raw = params.require(:user)
            user.team_ids = Team.where(id: raw[:team_ids]).ids if raw.key?(:team_ids)
            if raw.key?(:scoped_account_ids)
              user.scoped_account_ids = Organisation.where(id: raw[:scoped_account_ids]).ids
            end
          end
        end
        saved
      end
    end
  end
end
