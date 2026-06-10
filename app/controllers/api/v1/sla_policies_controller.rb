module Api
  module V1
    class SlaPoliciesController < BaseController
      before_action :set_policy, only: %i[show update destroy]

      def index
        records = api_scope(SlaPolicy, scope: "config:read").includes(:sla_targets).order(:name)
        render json: { data: records.map { |p| Serialize.sla_policy(p) } }
      end

      def show
        authorize_api!(@sla_policy, :show?, scope: "config:read")
        render json: { data: Serialize.sla_policy(@sla_policy) }
      end

      def create
        authorize_api!(SlaPolicy.new, :create?, scope: "config:write")
        policy = SlaPolicy.new(policy_params)
        if policy.save
          render json: { data: Serialize.sla_policy(policy) }, status: :created
        else
          render_validation_errors(policy)
        end
      end

      def update
        authorize_api!(@sla_policy, :update?, scope: "config:write")
        if @sla_policy.update(policy_params)
          render json: { data: Serialize.sla_policy(@sla_policy.reload) }
        else
          render_validation_errors(@sla_policy)
        end
      end

      def destroy
        authorize_api!(@sla_policy, :destroy?, scope: "config:write")
        @sla_policy.destroy
        head :no_content
      end

      private

      def set_policy
        @sla_policy = SlaPolicy.find(params[:id])
      end

      def policy_params
        params.require(:sla_policy).permit(:name, :description,
          sla_targets_attributes: %i[id priority first_response_minutes resolution_minutes _destroy])
      end
    end
  end
end
