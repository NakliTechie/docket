class PipelinesController < ApplicationController
  before_action :set_pipeline, only: %i[edit update destroy]

  def index
    authorize Pipeline
    @pipelines = policy_scope(Pipeline).includes(:pipeline_stages).order(:position, :id)
  end

  DEFAULT_STAGES = [
    { name: "New", position: 0, probability: 10 },
    { name: "Contacted", position: 1, probability: 25 },
    { name: "Qualified", position: 2, probability: 50 },
    { name: "Proposal", position: 3, probability: 75 },
    { name: "Won", position: 4, probability: 100, is_won: true },
    { name: "Lost", position: 5, probability: 0, is_lost: true }
  ].freeze

  def new
    @pipeline = Pipeline.new
    DEFAULT_STAGES.each { |attrs| @pipeline.pipeline_stages.build(attrs) }
    authorize @pipeline
  end

  def create
    @pipeline = Pipeline.new(pipeline_params)
    authorize @pipeline
    if @pipeline.save
      redirect_to pipelines_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @pipeline
  end

  def update
    authorize @pipeline
    if @pipeline.update(pipeline_params)
      redirect_to pipelines_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @pipeline
    @pipeline.destroy
    redirect_to pipelines_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_pipeline
    @pipeline = Pipeline.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name, :slug, :position, :active,
      pipeline_stages_attributes: %i[id name position probability is_won is_lost _destroy])
  end
end
