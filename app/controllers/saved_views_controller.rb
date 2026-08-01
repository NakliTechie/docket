class SavedViewsController < ApplicationController
  def create
    resource_type = params.require(:resource_type).to_s
    context_id = normalized_context(resource_type)
    view = SavedView.new(
      user: Current.user, name: params.require(:name), resource_type: resource_type,
      context_id: context_id,
      filters: SavedView.sanitize_filters(resource_type, params.fetch(:filters, {}))
    )
    authorize view
    if view.save
      redirect_to destination(view), notice: t("saved_views.create.created")
    else
      redirect_back fallback_location: cases_path,
                    alert: view.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    view = Current.user.saved_views.find(params[:id])
    authorize view
    destination_path = destination(view, include_view: false)
    view.destroy!
    redirect_to destination_path, notice: t("saved_views.destroy.deleted"), status: :see_other
  end

  private

  def normalized_context(resource_type)
    return nil if resource_type == "cases"
    raise ActionController::BadRequest, "context_id is required" unless resource_type == "work_items"

    policy_scope(Project).find(params.require(:context_id)).id
  end

  def destination(view, include_view: true)
    options = include_view ? { saved_view_id: view.id } : {}
    return cases_path(options) if view.resource_type == "cases"

    project_work_items_path(view.context_id, options)
  end
end
