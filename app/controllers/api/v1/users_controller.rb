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
        user = User.new(user_params)
        if user.save
          render json: { data: Serialize.user(user) }, status: :created
        else
          render_validation_errors(user)
        end
      end

      def update
        authorize @user
        attrs = user_params
        attrs = attrs.except(:password) if attrs[:password].blank?
        if @user.update(attrs)
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
        params.require(:user).permit(:name, :email_address, :password, :role, :locale, :active, queue_ids: [])
      end
    end
  end
end
