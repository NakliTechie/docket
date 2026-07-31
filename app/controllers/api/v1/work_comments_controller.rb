module Api
  module V1
    class WorkCommentsController < BaseController
      require_feature "work"
      before_action :set_item, only: %i[index create]
      before_action :set_comment, only: %i[update destroy]

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

      def update
        authorize_comment!(:update?)
        if @comment.update(comment_params)
          render json: { data: Serialize.work_comment(@comment) }
        else
          render_validation_errors(@comment)
        end
      end

      def destroy
        authorize_comment!(:destroy?)
        @comment.destroy
        head :no_content
      end

      private

      def set_item
        required_scope = action_name == "index" ? "work:read" : "work:write"
        @item = api_scope(WorkItem, scope: required_scope).find(params[:work_item_id])
      end

      def set_comment
        @comment = api_scope(WorkComment, scope: "work:write").find(params[:id])
      end

      def authorize_comment!(query)
        authorize_api!(@comment, query, scope: "work:write")
        return if current_user || @comment.author == service_account

        raise ScopeDenied, "comment ownership"
      end

      def comment_params
        params.require(:work_comment).permit(:body)
      end
    end
  end
end
