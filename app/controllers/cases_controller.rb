class CasesController < ApplicationController
  require_feature "service_desk"
  before_action :set_case, only: %i[show edit update destroy transition assign run_agent escalate merge split]

  # Optimistic-locking conflict: someone else changed this case since it was
  # loaded. Don't clobber — ask the agent to reload and retry.
  rescue_from ActiveRecord::StaleObjectError do
    redirect_to(@case || cases_path, alert: t("cases.stale_conflict"), status: :see_other)
  end

  def index
    @saved_views = Current.user.saved_views.for_resource("cases").order(:name)
    @current_saved_view = @saved_views.find_by(id: params[:saved_view_id])
    @filters = @current_saved_view ? ActionController::Parameters.new(@current_saved_view.filters) : filter_params
    scope = policy_scope(Case).canonical.includes(:contact, :queue, :assignee, :category)
    @has_any_cases = scope.exists?
    cases = scope.search(@filters[:q])
    cases = cases.where(status: @filters[:status]) if @filters[:status].present?
    cases = cases.where(priority: @filters[:priority]) if @filters[:priority].present?
    cases = cases.where(queue_id: @filters[:queue_id]) if @filters[:queue_id].present?
    cases = cases.where(assignee_id: @filters[:assignee_id]) if @filters[:assignee_id].present?
    @pagy, @cases = pagy(cases.order(sort_clause))
  end

  def bulk_update
    cases = selected_cases
    action = params.require(:bulk_action)
    cases.each { |kase| authorize kase, bulk_policy_action(action) }

    result = Case.transaction do
      case action
      when "assign" then bulk_assign(cases)
      when "transition" then bulk_transition(cases)
      when "priority" then bulk_priority(cases)
      else raise ActionController::BadRequest, "unsupported bulk action"
      end
    end
    redirect_back fallback_location: cases_path,
                  notice: t("cases.bulk_update.updated", count: cases.size, submitted: result[:submitted])
  end

  def show
    authorize @case
    CasePresence.touch_for!(@case, Current.user)
    @active_presences = CasePresence.active.where(case: @case).where.not(user: Current.user).includes(:user)
    @messages = @case.messages.with_attached_files.includes(:author).order(:created_at)
    @call_records = @case.call_records.includes(:connector).order(:created_at)
    @message = Message.new(kind: params[:note] ? :internal_note : :public_reply,
                           body: flash[:compose_body]) # preserved after a failed save (M30)
    @contact_cases = policy_scope(Case).where(contact: @case.contact).where.not(id: @case.id)
                                      .order(created_at: :desc).limit(10)
    @macros = Macro.order(:name)
    @next_case = next_open_case
    @merge_candidates = policy_scope(Case).canonical.where(contact: @case.contact).where.not(id: @case.id)
                                    .order(created_at: :desc).limit(100)
    @linked_work_items = if feature?("work") && policy(WorkItem).index?
      policy_scope(WorkItem).where(id: @case.work_items.select(:id)).includes(:project, :workflow_state)
    else
      WorkItem.none
    end
  end

  def new
    @case = Case.new(contact_id: params[:contact_id], channel: :staff, owner: Current.user)
    @inline_contact = Contact.new(preferred_language: I18n.locale, owner: Current.user)
    authorize @case
  end

  def create
    @case = Case.new(case_params)
    @case.channel = :staff
    @case.owner ||= Current.user
    @inline_contact = Contact.new(inline_contact_params.merge(preferred_language: I18n.locale,
                                                               owner: Current.user))
    authorize @case
    if inline_contact_requested?
      authorize @inline_contact
      @case.contact = @inline_contact
    end

    if save_case_with_inline_contact
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
    attributes = case_update_params
    custom_fields = attributes.delete(:custom_fields)
    @case.assign_attributes(attributes)
    @case.assign_custom_fields(custom_fields) if custom_fields
    if @case.save
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

    # Maker-checker (PG4/W3): a guarded transition (e.g. closure) parks for a
    # checker; an unguarded one goes straight through.
    if @case.guarded_transition_to(to, requested_by: Current.user)
      redirect_to @case, notice: t(".transitioned", status: @case.human_status)
    else
      redirect_to @case, notice: t(".submitted_for_approval")
    end
  end

  def assign
    authorize @case
    assignee = params[:assignee_id].presence && User.case_assignees.find_by(id: params[:assignee_id])
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

  # WM4: hand a case to engineering. Requires BOTH modules — the button only
  # appears when the tenant has work, and this re-checks it.
  def escalate
    authorize @case, :update?
    return head(:not_found) unless feature?("work")
    raise Pundit::NotAuthorizedError unless Current.user.can?("work:write")

    project = policy_scope(Project).active.find(params[:project_id])
    result = Work::Escalation.call(kase: @case, project: project, actor: Current.user,
                                   title: params[:title].presence,
                                   kind: params[:kind].presence || :bug)
    redirect_to case_path(@case),
                notice: t(".escalated", reference: result.work_item.reference)
  end

  def merge
    authorize @case, :merge?
    source = policy_scope(Case).canonical.find(params.require(:source_case_id))
    authorize source, :merge?
    CaseMerge.call(source: source, target: @case, actor: Current.user)
    redirect_to case_path(@case), notice: t(".merged", tracking_id: source.tracking_id)
  rescue ArgumentError => error
    redirect_to case_path(@case), alert: error.message, status: :see_other
  end

  def split
    authorize @case, :split?
    created = CaseSplit.call(source: @case, message_ids: params[:message_ids],
                             subject: params[:subject], actor: Current.user)
    redirect_to case_path(created), notice: t(".split", tracking_id: created.tracking_id)
  rescue ArgumentError => error
    redirect_to case_path(@case), alert: error.message, status: :see_other
  end

  private

  # Next-case hotkey target: oldest open case in the same queue, else
  # oldest open case anywhere.
  def next_open_case
    base = policy_scope(Case).open_cases.where.not(id: @case.id)
    (@case.queue_id && base.where(queue_id: @case.queue_id).order(:created_at).first) ||
      base.order(:created_at).first
  end

  def set_case
    @case = Case.find(params[:id]).canonical_record
  end

  def case_params
    params.require(:case).permit(:subject, :description, :priority, :category_id,
                                 :queue_id, :assignee_id, :owner_id, :contact_id, :sla_policy_id,
                                 custom_fields: {})
  end

  def inline_contact_params
    params.fetch(:new_contact, ActionController::Parameters.new).permit(:name, :email, :phone)
  end

  def inline_contact_requested?
    @inline_contact.name.present? || @inline_contact.email.present? || @inline_contact.phone.present?
  end

  def save_case_with_inline_contact
    return @case.save unless inline_contact_requested?

    case_valid = @case.valid?
    contact_valid = @inline_contact.valid?
    return false unless case_valid && contact_valid

    Case.transaction do
      @inline_contact.save!
      @case.save!
    end
    true
  end

  # contact_id is set when the case is created; repointing it via the edit
  # form would silently move a case's whole thread/history to a different
  # contact, so it's not mass-assignable on update. lock_version IS accepted
  # so the submitted (possibly stale) value drives optimistic-lock detection.
  def case_update_params
    params.require(:case).permit(:subject, :description, :priority, :category_id,
                                 :queue_id, :assignee_id, :owner_id, :sla_policy_id, :lock_version,
                                 custom_fields: {})
  end

  def filter_params
    params.permit(:q, :status, :priority, :queue_id, :assignee_id, :sort, :dir, :page)
  end

  def selected_cases
    ids = Array(params[:case_ids]).map(&:to_s).uniq
    raise ActionController::BadRequest, "select between 1 and 100 cases" unless ids.size.between?(1, 100)

    records = policy_scope(Case).where(id: ids).to_a
    raise ActiveRecord::RecordNotFound unless records.size == ids.size

    records
  end

  def bulk_policy_action(action)
    { "assign" => :assign?, "transition" => :transition?, "priority" => :update? }
      .fetch(action) { raise ActionController::BadRequest, "unsupported bulk action" }
  end

  def bulk_assign(cases)
    assignee_id = params[:assignee_id].presence
    assignee = assignee_id && User.case_assignees.find_by(id: assignee_id)
    raise ActionController::BadRequest, "invalid assignee" if assignee_id && assignee.nil?

    cases.each { |kase| kase.update!(assignee: assignee) }
    { submitted: 0 }
  end

  def bulk_transition(cases)
    status = params.require(:status).to_s
    raise ActionController::BadRequest, "invalid status" unless Case.statuses.key?(status)

    submitted = cases.count do |kase|
      !kase.guarded_transition_to(status, requested_by: Current.user)
    end
    { submitted: submitted }
  end

  def bulk_priority(cases)
    priority = params.require(:priority).to_s
    raise ActionController::BadRequest, "invalid priority" unless Case.priorities.key?(priority)

    cases.each { |kase| kase.update!(priority: priority) }
    { submitted: 0 }
  end

  SORTABLE = { "created_at" => "cases.created_at", "priority" => "cases.priority",
               "status" => "cases.status", "due" => "cases.resolution_due_at" }.freeze

  def sort_clause
    column = SORTABLE.fetch(@filters[:sort], "cases.created_at")
    direction = @filters[:dir] == "asc" ? :asc : :desc
    { Arel.sql(column) => direction }
  end
end
