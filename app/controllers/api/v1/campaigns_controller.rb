module Api
  module V1
    class CampaignsController < BaseController
      require_feature "crm"
      before_action :set_campaign, only: %i[show update destroy]

      def index
        pagy, records = pagy(api_scope(Campaign, scope: "crm:read").order(created_at: :desc))
        render json: { data: records.map { |campaign| Serialize.campaign(campaign) },
                       pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@campaign, :show?, scope: "crm:read")
        render json: { data: Serialize.campaign(@campaign) }
      end

      def create
        campaign = Campaign.new(campaign_params)
        authorize_api!(campaign, :create?, scope: "crm:write")
        if campaign.save
          render json: { data: Serialize.campaign(campaign) }, status: :created
        else
          render_validation_errors(campaign)
        end
      end

      def update
        authorize_api!(@campaign, :update?, scope: "crm:write")
        if @campaign.update(campaign_params)
          render json: { data: Serialize.campaign(@campaign) }
        else
          render_validation_errors(@campaign)
        end
      end

      def destroy
        authorize_api!(@campaign, :destroy?, scope: "crm:write")
        @campaign.destroy
        head :no_content
      end

      private

      def set_campaign
        scope = action_name == "show" ? "crm:read" : "crm:write"
        @campaign = api_scope(Campaign, scope: scope).find(params[:id])
      end

      def campaign_params
        params.require(:campaign).permit(
          :name, :code, :description, :status, :channel, :starts_on, :ends_on,
          :budget_cents, :currency, :utm_source, :utm_medium, :utm_campaign
        )
      end
    end
  end
end
