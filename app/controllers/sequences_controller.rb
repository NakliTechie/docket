class SequencesController < ApplicationController
  require_feature "crm.sequences"
  before_action :set_sequence, only: %i[show edit update destroy]

  def index
    authorize Sequence
    @sequences = policy_scope(Sequence).includes(:sequence_steps).order(:name)
  end

  def show
    authorize @sequence
    @enrollments = @sequence.sequence_enrollments
                            .includes(:enrollable, :sequence_deliveries)
                            .order(created_at: :desc)
    @analytics = @sequence.delivery_analytics
  end

  def new
    @sequence = Sequence.new
    @sequence.sequence_steps.build(position: 0, delay_days: 0, delay_hours: 0)
    authorize @sequence
  end

  def create
    @sequence = Sequence.new(sequence_params)
    authorize @sequence
    if @sequence.save
      redirect_to @sequence, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @sequence
  end

  def update
    authorize @sequence
    if @sequence.update(sequence_params)
      redirect_to @sequence, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @sequence
    @sequence.destroy
    redirect_to sequences_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_sequence
    @sequence = Sequence.find(params[:id])
  end

  def sequence_params
    params.require(:sequence).permit(:name, :active, :owner_id, :business_calendar_id,
      sequence_steps_attributes: %i[
        id position delay_days delay_hours use_business_hours template_key channel subject body _destroy
      ])
  end
end
