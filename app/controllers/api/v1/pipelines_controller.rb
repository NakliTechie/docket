module Api
  module V1
    class PipelinesController < BaseController
      before_action :set_pipeline, only: %i[show update destroy]

      def index
        pagy, records = pagy(api_scope(Pipeline, scope: "crm:read").order(:position, :id))
        render json: { data: records.map { |p| Serialize.pipeline(p) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@pipeline, :show?, scope: "crm:read")
        render json: { data: Serialize.pipeline(@pipeline) }
      end

      def create
        authorize_api!(Pipeline.new, :create?, scope: "crm:write")
        pipeline = Pipeline.new(pipeline_params)
        if pipeline.save
          render json: { data: Serialize.pipeline(pipeline) }, status: :created
        else
          render_validation_errors(pipeline)
        end
      end

      def update
        authorize_api!(@pipeline, :update?, scope: "crm:write")
        if @pipeline.update(pipeline_params)
          render json: { data: Serialize.pipeline(@pipeline) }
        else
          render_validation_errors(@pipeline)
        end
      end

      def destroy
        authorize_api!(@pipeline, :destroy?, scope: "crm:write")
        @pipeline.destroy
        head :no_content
      end

      private

      def set_pipeline
        @pipeline = Pipeline.find(params[:id])
      end

      def pipeline_params
        params.require(:pipeline).permit(:name, :slug, :position, :active,
          pipeline_stages_attributes: %i[id name position probability is_won is_lost _destroy])
      end
    end
  end
end
