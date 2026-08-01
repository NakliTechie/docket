module Api
  module V1
    class WorkItemRelationsController < BaseController
      require_feature "work"

      def create
        source = api_scope(WorkItem, scope: "work:write").find(params[:work_item_id])
        target = api_scope(WorkItem, scope: "work:write").find(relation_params[:target_id])
        relation = WorkItemRelation.new(source: source, target: target,
                                        relation_type: relation_params[:relation_type],
                                        created_by: current_user)
        authorize_api!(relation, :create?, scope: "work:write")
        relation.save!
        render json: { data: Serialize.work_item_relation(relation) }, status: :created
      end

      def destroy
        relation = WorkItemRelation.find(params[:id])
        authorize_api!(relation, :destroy?, scope: "work:write")
        relation.destroy!
        head :no_content
      end

      private

      def relation_params
        params.require(:work_item_relation).permit(:target_id, :relation_type)
      end
    end
  end
end
