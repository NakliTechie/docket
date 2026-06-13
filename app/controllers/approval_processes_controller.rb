# Admin CRUD for maker-checker rules (PG4). Each process declares an entry
# criterion — a guarded case transition or an escalated effector action.
class ApprovalProcessesController < ApplicationController
  before_action :set_process, only: %i[edit update destroy]

  def index
    authorize ApprovalProcess
    @processes = policy_scope(ApprovalProcess).ordered
  end

  def new
    @process = ApprovalProcess.new
    authorize @process
  end

  def create
    @process = ApprovalProcess.new(process_params)
    authorize @process
    if @process.save
      redirect_to approval_processes_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @process
  end

  def update
    authorize @process
    if @process.update(process_params)
      redirect_to approval_processes_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @process
    @process.destroy
    redirect_to approval_processes_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_process
    @process = ApprovalProcess.find(params[:id])
  end

  def process_params
    params.require(:approval_process).permit(:name, :trigger_type, :trigger_key, :active)
  end
end
