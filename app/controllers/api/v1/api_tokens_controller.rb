module Api
  module V1
    # Token issuance/revocation — admin-only, human-only. The raw token
    # appears exactly once in the create response.
    class ApiTokensController < BaseController
      before_action :require_admin_human!

      def index
        pagy, records = pagy(ApiToken.order(id: :desc))
        render json: { data: records.map { |t| Serialize.api_token(t) }, pagination: pagination_meta(pagy) }
      end

      def create
        token = ApiToken.new(token_params)
        if token.save
          render json: { data: Serialize.api_token(token).merge(token: token.raw_token) }, status: :created
        else
          render_validation_errors(token)
        end
      end

      def destroy
        token = ApiToken.find(params[:id])
        token.revoke!
        head :no_content
      end

      private

      def require_admin_human!
        raise ScopeDenied, "api_token:manage" unless current_user&.can?("api_token:manage")
      end

      def token_params
        params.require(:api_token).permit(:user_id, :name)
      end
    end
  end
end
