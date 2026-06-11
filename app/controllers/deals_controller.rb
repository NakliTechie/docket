class DealsController < ApplicationController
  before_action :set_deal, only: %i[show edit update destroy move]

  # Kanban board: open deals grouped by stage for the selected pipeline.
  def index
    @pipelines = Pipeline.active.order(:position, :id)
    @pipeline = (params[:pipeline_id].present? && Pipeline.find_by(id: params[:pipeline_id])) || Pipeline.default
    if @pipeline
      @stages = @pipeline.pipeline_stages.order(:position)
      deals = policy_scope(Deal).where(pipeline: @pipeline).includes(:owner, :contact).order(updated_at: :desc)
      @deals_by_stage = deals.group_by(&:pipeline_stage_id)
    else
      @stages = []
      @deals_by_stage = {}
    end
  end

  def show
    authorize @deal
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

  private

  def set_deal
    @deal = Deal.find(params[:id])
  end

  def deal_params
    params.require(:deal).permit(:name, :pipeline_id, :pipeline_stage_id, :owner_id,
                                 :contact_id, :organisation_id, :value, :currency, :expected_close_on)
  end
end
