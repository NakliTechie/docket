module Api
  module V1
    class CompetitorsController < BaseController
      require_feature "crm"
      before_action :set_competitor, only: %i[show update destroy]

      def index
        records = api_scope(Competitor, scope: "crm:read").order(:name)
        render json: { data: records.map { |competitor| Serialize.competitor(competitor) } }
      end

      def show
        authorize_api!(@competitor, :show?, scope: "crm:read")
        render json: { data: Serialize.competitor(@competitor) }
      end

      def create
        competitor = Competitor.new(competitor_params)
        authorize_api!(competitor, :create?, scope: "crm:write")
        competitor.save ? render(json: { data: Serialize.competitor(competitor) }, status: :created) : render_validation_errors(competitor)
      end

      def update
        authorize_api!(@competitor, :update?, scope: "crm:write")
        @competitor.update(competitor_params) ? render(json: { data: Serialize.competitor(@competitor) }) : render_validation_errors(@competitor)
      end

      def destroy
        authorize_api!(@competitor, :destroy?, scope: "crm:write")
        @competitor.destroy ? head(:no_content) : render_validation_errors(@competitor)
      end

      private

      def set_competitor
        scope = action_name == "show" ? "crm:read" : "crm:write"
        @competitor = api_scope(Competitor, scope: scope).find(params[:id])
      end

      def competitor_params
        params.require(:competitor).permit(:name, :website, :notes)
      end
    end
  end
end
