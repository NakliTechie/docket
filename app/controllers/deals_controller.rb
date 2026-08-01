class DealsController < ApplicationController
  require_feature "crm"

  # A pipeline is a working surface, not a report. See the deal list for all.
  STAGE_LIMIT = 50
  before_action :set_deal, only: %i[show edit update destroy move onboard engage]

  # Kanban board: open deals grouped by stage for the selected pipeline.
  def index
    @pipelines = Pipeline.active.order(:position, :id)
    @pipeline = (params[:pipeline_id].present? && Pipeline.find_by(id: params[:pipeline_id])) || Pipeline.default
    if @pipeline
      @stages = @pipeline.pipeline_stages.order(:position)
      # Same per-column cap as the work board, for the same reason: this loaded
      # every open deal in the pipeline and grouped in Ruby.
      scope = policy_scope(Deal).where(pipeline: @pipeline).includes(:owner, :contact)
      @stage_limit = STAGE_LIMIT
      @totals_by_stage = scope.reorder(nil).group(:pipeline_stage_id).count
      @deals_by_stage = @stages.each_with_object({}) do |stage, acc|
        acc[stage.id] = scope.where(pipeline_stage_id: stage.id)
                             .order(updated_at: :desc)
                             .limit(STAGE_LIMIT)
                             .to_a
      end
    else
      @stages = []
      @deals_by_stage = {}
    end
  end

  def show
    authorize @deal
    @project_templates = policy_scope(ProjectTemplate).active.order(:name) if feature?("work")
    @line_item = DealLineItem.new(deal: @deal)
    @available_products = policy_scope(Product).active.where(currency: @deal.currency)
                                .where.not(id: @deal.product_ids).order(:name)
    @deal_competitor = DealCompetitor.new(deal: @deal)
    @available_competitors = policy_scope(Competitor).where.not(id: @deal.competitor_ids).order(:name)
    @deal_contact_role = DealContactRole.new(deal: @deal)
    @available_role_contacts = Contact.where.not(id: @deal.role_contacts.select(:id)).order(:name)
  end

  def new
    @deal = Deal.new(pipeline: Pipeline.default)
    @deal.pipeline_stage = @deal.pipeline&.first_stage
    authorize @deal
  end

  def create
    @deal = Deal.new(deal_params)
    authorize @deal
    if @deal.save
      redirect_to @deal, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @deal
  end

  def update
    authorize @deal
    if @deal.update(deal_params)
      redirect_to @deal, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @deal
    @deal.destroy
    redirect_to deals_path, notice: t(".deleted"), status: :see_other
  end

  # The kanban drag: move a card to another stage in the same pipeline.
  def move
    authorize @deal, :move?
    stage = @deal.pipeline.pipeline_stages.find(params[:pipeline_stage_id])
    @deal.move_to_stage!(stage)
    respond_to do |format|
      format.json { render json: { id: @deal.id, stage_id: stage.id, status: @deal.status } }
      format.html { redirect_to deals_path, notice: t(".moved") }
    end
  end

  def onboard
    authorize @deal
    raise Pundit::NotAuthorizedError unless feature?("work")

    template = policy_scope(ProjectTemplate).active.find(params.require(:project_template_id))
    project = DealOnboarding.call(deal: @deal, template: template, actor: Current.user)
    redirect_to project_path(project), notice: t(".created", project: project.display_label)
  rescue DealOnboarding::Error => error
    redirect_to deal_path(@deal), alert: error.message, status: :see_other
  end

  # Start an engagement project (pre-quote studies) from an OPEN deal.
  def engage
    authorize @deal
    raise Pundit::NotAuthorizedError unless feature?("work")

    template = policy_scope(ProjectTemplate).active.find(params.require(:project_template_id))
    project = DealOnboarding.call(deal: @deal, template: template, actor: Current.user, mode: :engagement)
    redirect_to project_path(project), notice: t(".created", project: project.display_label)
  rescue DealOnboarding::Error => error
    redirect_to deal_path(@deal), alert: error.message, status: :see_other
  end

  private

  def set_deal
    @deal = Deal.find(params[:id])
  end

  def deal_params
    params.require(:deal).permit(:name, :pipeline_id, :pipeline_stage_id, :owner_id,
                                 :contact_id, :organisation_id, :value, :currency, :expected_close_on,
                                 :lost_reason)
  end
end
