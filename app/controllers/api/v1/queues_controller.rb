module Api
  module V1
    class QueuesController < BaseController
      before_action :set_queue, only: %i[show update destroy]

      def index
        records = api_scope(CaseQueue, scope: "config:read").order(:name)
        render json: { data: records.map { |q| Serialize.queue(q) } }
      end

      def show
        authorize_api!(@queue, :show?, scope: "config:read")
        render json: { data: Serialize.queue(@queue) }
      end

      def create
        authorize_api!(CaseQueue.new, :create?, scope: "config:write")
        queue = CaseQueue.new(queue_params)
        if queue.save
          render json: { data: Serialize.queue(queue) }, status: :created
        else
          render_validation_errors(queue)
        end
      end

      def update
        authorize_api!(@queue, :update?, scope: "config:write")
        if @queue.update(queue_params)
          render json: { data: Serialize.queue(@queue) }
        else
          render_validation_errors(@queue)
        end
      end

      def destroy
        authorize_api!(@queue, :destroy?, scope: "config:write")
        @queue.destroy
        head :no_content
      end

      private

      def set_queue
        @queue = CaseQueue.find_by(slug: params[:id]) || CaseQueue.find(params[:id])
      end

      def queue_params
        params.require(:queue).permit(:name, :slug, :description, member_ids: [])
      end
    end
  end
end
