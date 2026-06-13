module Admin
  class WebhookEndpointsController < ApplicationController
    before_action :set_endpoint, only: %i[edit update destroy deliveries]

    def index
      authorize :webhooks, policy_class: PlatformAreaPolicy
      @endpoints = WebhookEndpoint.order(:name)
    end

    def new
      authorize :webhooks, policy_class: PlatformAreaPolicy
      @endpoint = WebhookEndpoint.new
    end

    def create
      authorize :webhooks, policy_class: PlatformAreaPolicy
      @endpoint = WebhookEndpoint.new(endpoint_params)
      if @endpoint.save
        flash[:webhook_secret] = @endpoint.secret
        redirect_to admin_webhook_endpoints_path, notice: t(".created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize :webhooks, policy_class: PlatformAreaPolicy
    end

    def update
      authorize :webhooks, policy_class: PlatformAreaPolicy
      if @endpoint.update(endpoint_params)
        redirect_to admin_webhook_endpoints_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize :webhooks, policy_class: PlatformAreaPolicy
      @endpoint.destroy
      redirect_to admin_webhook_endpoints_path, notice: t(".deleted"), status: :see_other
    end

    def deliveries
      authorize :webhooks, policy_class: PlatformAreaPolicy
      @pagy, @deliveries = pagy(@endpoint.webhook_deliveries.recent_first)
    end

    private

    def set_endpoint
      @endpoint = WebhookEndpoint.find(params[:id])
    end

    def endpoint_params
      permitted = params.require(:webhook_endpoint).permit(:name, :url, :active, events: [])
      # Drop the empty-string companion so an all-unchecked submission
      # becomes [] and surfaces the "at least one event" validation error.
      permitted[:events] = Array(permitted[:events]).reject(&:blank?) if permitted.key?(:events)
      permitted
    end
  end
end
