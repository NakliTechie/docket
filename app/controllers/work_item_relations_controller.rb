class WorkItemRelationsController < ApplicationController
  require_feature "work"

  def create
    source = policy_scope(WorkItem).find(params[:work_item_id])
    target = policy_scope(WorkItem).find(relation_params[:target_id])
    relation = WorkItemRelation.new(source: source, target: target,
                                    relation_type: relation_params[:relation_type],
                                    created_by: Current.user)
    authorize relation
    if relation.save
      redirect_to work_item_path(source), notice: t(".created")
    else
      redirect_to work_item_path(source), alert: relation.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  def destroy
    relation = WorkItemRelation.find(params[:id])
    authorize relation
    return_to = relation.source
    relation.destroy!
    redirect_to work_item_path(return_to), notice: t(".deleted"), status: :see_other
  end

  private

  def relation_params
    params.require(:work_item_relation).permit(:target_id, :relation_type)
  end
end
