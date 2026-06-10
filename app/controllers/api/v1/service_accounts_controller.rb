module Api
  module V1
    # Service-account lifecycle — admin-only, human-only. The client
    # secret appears exactly once on create and on rotation.
    class ServiceAccountsController < BaseController
      before_action :require_admin_human!
      before_action :set_account, only: %i[show update destroy rotate_secret]

      def index
        pagy, records = pagy(ServiceAccount.order(:name))
        render json: { data: records.map { |s| Serialize.service_account(s) }, pagination: pagination_meta(pagy) }
      end

      def show
        render json: { data: Serialize.service_account(@service_account) }
      end

      def create
        account = ServiceAccount.new(account_params)
        if account.save
          render json: { data: Serialize.service_account(account).merge(client_secret: account.raw_client_secret) },
                 status: :created
        else
          render_validation_errors(account)
        end
      end

      def update
        if @service_account.update(account_params)
          @service_account.deactivate! unless @service_account.active
          render json: { data: Serialize.service_account(@service_account) }
        else
          render_validation_errors(@service_account)
        end
      end

      def destroy
        @service_account.deactivate!
        @service_account.destroy
        head :no_content
      end

      def rotate_secret
        secret = @service_account.rotate_secret!
        render json: { data: Serialize.service_account(@service_account).merge(client_secret: secret) }
      end

      private

      def require_admin_human!
        raise ScopeDenied, "admin" unless current_user&.role_admin?
      end

      def set_account
        @service_account = ServiceAccount.find(params[:id])
      end

      def account_params
        params.require(:service_account).permit(:name, :description, :active, scopes: [])
      end
    end
  end
end
