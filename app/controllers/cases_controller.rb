class CasesController < ApplicationController
  before_action :set_case, only: %i[show edit update destroy transition assign run_agent]

  # Optimistic-locking conflict: someone else changed this case since it was
  # loaded. Don't clobber — ask the agent to reload and retry.
  rescue_from ActiveRecord::StaleObjectError do
    redirect_to(@case || cases_path, alert: t("cases.stale_conflict"), status: :see_other)
  end

  def index
    @filters = filter_params
    cases = policy_scope(Case)
              .includes(:contact, :queue, :assignee, :category)
              .search(@filters[:q])
    cases = cases.where(status: @filters[:status]) if @filters[:status].present?
    cases = cases.where(priority: @filters[:priority]) if @filters[:priority].present?
    cases = cases.where(queue_id: @filters[:queue_id]) if @filters[:queue_id].present?
    cases = cases.where(assignee_id: @filters[:assignee_id]) if @filters[:assignee_id].present?
    @pagy, @cases = pagy(cases.order(sort_clause))
  end

  def show
    authorize @case
    @messages = @case.messages.with_attached_files.includes(:author).order(:created_at)
    @message = Message.new(kind: params[:note] ? :internal_note : :public_reply,
                           body: flash[:compose_body]) # preserved after a failed save (M30)
    @contact_cases = @case.contact.cases.where.not(id: @case.id).order(created_at: :desc).limit(10)
    @macros = Macro.order(:name)
    @next_case = next_open_case
  end

  def new
    @case = Case.new(contact_id: params[:contact_id], channel: :staff)
    authorize @case
  end

  def create
    @case = Case.new(case_params)
    @case.channel = :staff
    authorize @case
    if @case.save
      redirect_to @case, notice: t(".created", tracking_id: @case.tracking_id)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @case
  end

  def update
    authorize @case
    if @case.update(case_update_params)
      redirect_to @case, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @case
    if @case.destroy
      redirect_to cases_path, notice: t(".deleted"), status: :see_other
    else
      redirect_to @case, alert: @case.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def transition
    authorize @case
    to = params.require(:status)

    # Maker-checker (PG4): a guarded transition (e.g. closure) can't proceed
    # until a checker approves it — the maker's request is parked for review.
    if ApprovalGate.guarded_transition?(@case, to) && !ApprovalGate.transition_cleared?(@case, to)
      ApprovalGate.submit_transition!(@case, to, requested_by: Current.user)
      return redirect_to @case, notice: t(".submitted_for_approval")
    end

    @case.transition_to!(to)
    redirect_to @case, notice: t(".transitioned", status: @case.human_status)
  end

  def assign
    authorize @case
    assignee = params[:assignee_id].presence && User.active.find_by(id: params[:assignee_id])
    if params[:assignee_id].present? && assignee.nil? # unknown / inactive / other tenant (L2)
      return redirect_to @case, alert: t(".invalid_assignee"), status: :see_other
    end
    @case.update!(assignee: assignee)
    redirect_to @case, notice: assignee ? t(".assigned", name: assignee.name) : t(".unassigned")
  end

  # Hand the case to the designated AI effector agent (runs off-request).
  # Write / decision-of-record actions it proposes land in the approval queue.
  def run_agent
    authorize @case, :update?
    agent = Connectors::AgentRunner.designated_agent
    if agent && Llm.enabled?
      Connectors::AgentRunner.run_later(@case, agent: agent)
      redirect_to @case, notice: t(".queued", name: agent.name)
    else
      redirect_to @case, alert: t(".unavailable")
    end
  end

  private

  # Next-case hotkey target: oldest open case in the same queue, else
  # oldest open case anywhere.
  def next_open_case
    base = Case.open_cases.where.not(id: @case.id)
    (@case.queue_id && base.where(queue_id: @case.queue_id).order(:created_at).first) ||
      base.order(:created_at).first
  end

  def set_case
    @case = Case.find(params[:id])
  end

  def case_params
    params.require(:case).permit(:subject, :description, :priority, :category_id,
                                 :queue_id, :assignee_id, :contact_id, :sla_policy_id)
  end

  # contact_id is set when the case is created; repointing it via the edit
  # form would silently move a case's whole thread/history to a different
  # contact, so it's not mass-assignable on update. lock_version IS accepted
  # so the submitted (possibly stale) value drives optimistic-lock detection.
  def case_update_params
    params.require(:case).permit(:subject, :description, :priority, :category_id,
                                 :queue_id, :assignee_id, :sla_policy_id, :lock_version)
  end

  def filter_params
    params.permit(:q, :status, :priority, :queue_id, :assignee_id, :sort, :dir, :page)
  end

  SORTABLE = { "created_at" => "cases.created_at", "priority" => "cases.priority",
               "status" => "cases.status", "due" => "cases.resolution_due_at" }.freeze

  def sort_clause
    column = SORTABLE.fetch(@filters[:sort], "cases.created_at")
    direction = @filters[:dir] == "asc" ? :asc : :desc
    { Arel.sql(column) => direction }
  end
end
