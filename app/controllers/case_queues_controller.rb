class CaseQueuesController < ApplicationController
  before_action :set_queue, only: %i[edit update destroy]

  def index
    @queues = policy_scope(CaseQueue).includes(:members).order(:name)
  end

  def new
    @queue = CaseQueue.new
    authorize @queue
  end

  def create
    @queue = CaseQueue.new(queue_params)
    authorize @queue
    if @queue.save
      redirect_to case_queues_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @queue
  end

  def update
    authorize @queue
    if @queue.update(queue_params)
      redirect_to case_queues_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @queue
    @queue.destroy
    redirect_to case_queues_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_queue
    @queue = CaseQueue.find(params[:id])
  end

  def queue_params
    params.require(:case_queue).permit(:name, :slug, :description, member_ids: [])
  end
end
