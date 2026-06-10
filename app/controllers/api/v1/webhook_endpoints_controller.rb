module Api
  module V1
    class WebhookEndpointsController < BaseController
      before_action :set_endpoint, only: %i[show update destroy deliveries]

      def index
        require_webhook_access!
        records = WebhookEndpoint.order(:name)
        render json: { data: records.map { |w| Serialize.webhook_endpoint(w) } }
      end

      def show
        require_webhook_access!
        render json: { data: Serialize.webhook_endpoint(@endpoint) }
      end

      def create
        require_webhook_access!
        endpoint = WebhookEndpoint.new(endpoint_params)
        if endpoint.save
          render json: { data: Serialize.webhook_endpoint(endpoint).merge(secret: endpoint.secret) },
                 status: :created
        else
          render_validation_errors(endpoint)
        end
      end

      def update
        require_webhook_access!
        if @endpoint.update(endpoint_params)
          render json: { data: Serialize.webhook_endpoint(@endpoint) }
        else
          render_validation_errors(@endpoint)
        end
      end

      def destroy
        require_webhook_access!
        @endpoint.destroy
        head :no_content
      end

      def deliveries
        require_webhook_access!
        pagy, records = pagy(@endpoint.webhook_deliveries.recent_first)
        render json: { data: records.map { |d| Serialize.webhook_delivery(d) }, pagination: pagination_meta(pagy) }
      end

      private

      def require_webhook_access!
        if current_user
          raise Pundit::NotAuthorizedError unless current_user.role_admin?
        else
          raise ScopeDenied, "webhooks:manage" unless current_access_token.scope?("webhooks:manage")
        end
      end

      def set_endpoint
        @endpoint = WebhookEndpoint.find(params[:id])
      end

      def endpoint_params
        params.require(:webhook_endpoint).permit(:name, :url, :active, events: [])
      end
    end
  end
end
