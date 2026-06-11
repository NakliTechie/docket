module Api
  module V1
    class DealsController < BaseController
      before_action :set_deal, only: %i[show update destroy move]

      def index
        scope = api_scope(Deal, scope: "crm:read")
        scope = scope.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        pagy, records = pagy(scope.order(updated_at: :desc))
        render json: { data: records.map { |d| Serialize.deal(d) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@deal, :show?, scope: "crm:read")
        render json: { data: Serialize.deal(@deal) }
      end

      def create
        authorize_api!(Deal.new, :create?, scope: "crm:write")
        deal = Deal.new(deal_params)
        if deal.save
          render json: { data: Serialize.deal(deal) }, status: :created
        else
          render_validation_errors(deal)
        end
      end

      def update
        authorize_api!(@deal, :update?, scope: "crm:write")
        if @deal.update(deal_params)
          render json: { data: Serialize.deal(@deal) }
        else
          render_validation_errors(@deal)
        end
      end

      def destroy
        authorize_api!(@deal, :destroy?, scope: "crm:write")
        @deal.destroy
        head :no_content
      end

      def move
        authorize_api!(@deal, :move?, scope: "crm:write")
        stage = @deal.pipeline.pipeline_stages.find(params[:pipeline_stage_id])
        @deal.move_to_stage!(stage)
        render json: { data: Serialize.deal(@deal) }
      end

      private

      def set_deal
        @deal = Deal.find(params[:id])
      end

      def deal_params
        params.require(:deal).permit(:name, :pipeline_id, :pipeline_stage_id, :owner_id,
                                     :contact_id, :organisation_id, :value, :currency, :expected_close_on)
      end
    end
  end
end
