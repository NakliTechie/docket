module Api
  module V1
    class DealCompetitorsController < BaseController
      require_feature "crm"
      before_action :set_link, only: %i[update destroy]

      def create
        deal = api_scope(Deal, scope: "crm:write").find(params[:deal_id])
        link = deal.deal_competitors.new(link_params)
        authorize_api!(link, :create?, scope: "crm:write")
        link.save ? render(json: { data: Serialize.deal_competitor(link) }, status: :created) : render_validation_errors(link)
      end

      def update
        authorize_api!(@link, :update?, scope: "crm:write")
        attributes = link_params.except(:competitor_id)
        @link.update(attributes) ? render(json: { data: Serialize.deal_competitor(@link) }) : render_validation_errors(@link)
      end

      def destroy
        authorize_api!(@link, :destroy?, scope: "crm:write")
        @link.destroy
        head :no_content
      end

      private

      def set_link
        @link = api_scope(DealCompetitor, scope: "crm:write").find(params[:id])
      end

      def link_params
        params.require(:deal_competitor).permit(:competitor_id, :disposition, :notes)
      end
    end
  end
end
