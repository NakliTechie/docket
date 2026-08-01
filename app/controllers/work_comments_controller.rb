class WorkCommentsController < ApplicationController
  require_feature "work"
  before_action :set_comment, only: %i[update destroy]

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

  def update
    authorize @comment
    if @comment.update(comment_params)
      redirect_to work_item_path(@comment.work_item), notice: t(".updated")
    else
      redirect_to work_item_path(@comment.work_item),
                  alert: @comment.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    authorize @comment
    item = @comment.work_item
    @comment.destroy
    redirect_to work_item_path(item), notice: t(".deleted"), status: :see_other
  end

  private

  def set_comment
    @comment = policy_scope(WorkComment).find(params[:id])
  end

  def comment_params
    params.require(:work_comment).permit(:body)
  end
end
