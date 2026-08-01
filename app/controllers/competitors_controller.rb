class CompetitorsController < ApplicationController
  require_feature "crm"
  before_action :set_competitor, only: %i[edit update destroy]

  def index
    authorize Competitor
    @competitors = policy_scope(Competitor).order(:name)
  end

  def new
    @competitor = Competitor.new
    authorize @competitor
  end

  def create
    @competitor = Competitor.new(competitor_params)
    authorize @competitor
    if @competitor.save
      redirect_to competitors_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @competitor
  end

  def update
    authorize @competitor
    if @competitor.update(competitor_params)
      redirect_to competitors_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @competitor
    if @competitor.destroy
      redirect_to competitors_path, notice: t(".deleted"), status: :see_other
    else
      redirect_to competitors_path, alert: @competitor.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  private

  def set_competitor
    @competitor = policy_scope(Competitor).find(params[:id])
  end

  def competitor_params
    params.require(:competitor).permit(:name, :website, :notes)
  end
end
