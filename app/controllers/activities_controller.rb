# PG2 — the rep task/interaction queue and per-subject activity logging.
# index is the "my open work" queue (filterable by owner + status); new/create
# are launched from a subject (Contact/Lead/Deal/Case) page carrying
# subject_type/subject_id; complete marks a task done.
class ActivitiesController < ApplicationController
  require_feature "crm"
  before_action :set_activity, only: %i[edit update destroy complete]

  SUBJECT_MODELS = { "Contact" => Contact, "Lead" => Lead, "Deal" => Deal, "Case" => Case }.freeze

  def index
    authorize Activity
    @owner_filter = params[:owner].presence_in(%w[mine all]) || "mine"
    @status_filter = params[:status].presence_in(%w[open done all]) || "open"

    scope = policy_scope(Activity)
    scope = scope.for_owner(Current.user) if @owner_filter == "mine"
    scope = scope.status_open if @status_filter == "open"
    scope = scope.status_done if @status_filter == "done"
    @pagy, @activities = pagy(scope.recent_first.includes(:subject, :owner))
  end

  def new
    @activity = Activity.new(subject: resolved_subject, owner: Current.user, kind: :call)
    authorize @activity
  end

  def create
    @activity = Activity.new(activity_params)
    authorize @activity
    if @activity.save
      redirect_back_or_to(activities_path, notice: t(".created"))
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @activity
  end

  def update
    authorize @activity
    if @activity.update(activity_params)
      redirect_to activities_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def complete
    authorize @activity, :complete?
    @activity.complete!
    redirect_back_or_to(activities_path, notice: t(".completed"))
  end

  def destroy
    authorize @activity
    @activity.destroy
    redirect_to activities_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_activity
    @activity = Activity.find(params[:id])
  end

  # Only the allowlisted polymorphic subjects, resolved tenant-scoped for #new.
  def resolved_subject
    model = SUBJECT_MODELS[params[:subject_type].to_s]
    model&.find_by(id: params[:subject_id])
  end

  def activity_params
    params.require(:activity).permit(:kind, :title, :body, :due_at, :owner_id, :status, :subject_type, :subject_id)
  end
end
