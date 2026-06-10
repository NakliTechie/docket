module Admin
  class WebhookEndpointsController < ApplicationController
    before_action :set_endpoint, only: %i[edit update destroy deliveries]

    def index
      authorize :webhooks, policy_class: AdminAreaPolicy
      @endpoints = WebhookEndpoint.order(:name)
    end

    def new
      authorize :webhooks, policy_class: AdminAreaPolicy
      @endpoint = WebhookEndpoint.new
    end

    def create
      authorize :webhooks, policy_class: AdminAreaPolicy
      @endpoint = WebhookEndpoint.new(endpoint_params)
      if @endpoint.save
        flash[:webhook_secret] = @endpoint.secret
        redirect_to admin_webhook_endpoints_path, notice: t(".created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize :webhooks, policy_class: AdminAreaPolicy
    end

    def update
      authorize :webhooks, policy_class: AdminAreaPolicy
      if @endpoint.update(endpoint_params)
        redirect_to admin_webhook_endpoints_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize :webhooks, policy_class: AdminAreaPolicy
      @endpoint.destroy
      redirect_to admin_webhook_endpoints_path, notice: t(".deleted"), status: :see_other
    end

    def deliveries
      authorize :webhooks, policy_class: AdminAreaPolicy
      @pagy, @deliveries = pagy(@endpoint.webhook_deliveries.recent_first)
    end

    private

    def set_endpoint
      @endpoint = WebhookEndpoint.find(params[:id])
    end

    def endpoint_params
      params.require(:webhook_endpoint).permit(:name, :url, :active, events: [])
    end
  end
end
