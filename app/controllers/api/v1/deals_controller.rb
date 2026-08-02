module Api
  module V1
    class DealsController < BaseController
      require_feature "crm"
      before_action :set_deal, only: %i[show update destroy move onboard engage]

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

      def onboard
        authorize_api!(@deal, :onboard?, scope: "crm:write")
        template = api_scope(ProjectTemplate, scope: "work:manage")
                   .active.find(params.require(:project_template_id))
        project = DealOnboarding.call(deal: @deal, template: template, actor: Current.actor)
        render json: { data: Serialize.project(project) }, status: :created
      rescue DealOnboarding::Error => error
        render_error("invalid_onboarding", detail: error.message, status: :unprocessable_entity)
      end

      # Start an engagement project (pre-quote studies) from an OPEN deal.
      def engage
        authorize_api!(@deal, :engage?, scope: "crm:write")
        template = api_scope(ProjectTemplate, scope: "work:manage")
                   .active.find(params.require(:project_template_id))
        project = DealOnboarding.call(deal: @deal, template: template, actor: Current.actor, mode: :engagement)
        render json: { data: Serialize.project(project) }, status: :created
      rescue DealOnboarding::Error => error
        render_error("invalid_engagement", detail: error.message, status: :unprocessable_entity)
      end

      private

      def set_deal
        @deal = Deal.find(params[:id])
      end

      def deal_params
        params.require(:deal).permit(:name, :pipeline_id, :pipeline_stage_id, :owner_id,
                                     :contact_id, :organisation_id, :value, :currency, :expected_close_on,
                                     :lost_reason, :first_touch_campaign_id)
      end
    end
  end
end
