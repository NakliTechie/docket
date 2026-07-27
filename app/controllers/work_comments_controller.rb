class WorkCommentsController < ApplicationController
  require_feature "work"

  def create
    @item = policy_scope(WorkItem).find(params[:work_item_id])
    @comment = @item.work_comments.new(body: params.require(:work_comment)[:body], author: Current.user)
    authorize @comment
    if @comment.save
      redirect_to work_item_path(@item), notice: t(".created")
    else
      redirect_to work_item_path(@item), alert: @comment.errors.full_messages.to_sentence
    end
  end
end
