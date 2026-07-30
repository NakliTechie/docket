module Api
  module V1
    class WorkCommentsController < BaseController
      require_feature "work"
      before_action :set_item

      def index
        authorize_api!(@item, :show?, scope: "work:read")
        render json: { data: @item.work_comments.map { |c| Serialize.work_comment(c) } }
      end

      def create
        comment = @item.work_comments.new(body: params.require(:work_comment)[:body],
                                          author: Current.actor)
        authorize_api!(comment, :create?, scope: "work:write")
        if comment.save
          render json: { data: Serialize.work_comment(comment) }, status: :created
        else
          render_validation_errors(comment)
        end
      end

      private

      def set_item
        @item = WorkItem.find(params[:work_item_id])
      end
    end
  end
end
