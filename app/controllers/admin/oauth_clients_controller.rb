module Admin
  class OauthClientsController < ApplicationController
    before_action :set_client, only: :destroy

    def index
      authorize :oauth_clients, policy_class: PlatformAreaPolicy
      @oauth_clients = OauthClient.order(created_at: :desc)
    end

    def destroy
      authorize :oauth_clients, policy_class: PlatformAreaPolicy
      @oauth_client.deactivate!
      redirect_to admin_oauth_clients_path, notice: t(".deactivated"), status: :see_other
    end

    private

    def set_client
      @oauth_client = OauthClient.find(params[:id])
    end
  end
end
