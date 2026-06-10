class MacrosController < ApplicationController
  before_action :set_macro, only: %i[edit update destroy]

  def index
    @macros = policy_scope(Macro).order(:name)
  end

  def new
    @macro = Macro.new
    authorize @macro
  end

  def create
    @macro = Macro.new(macro_params)
    authorize @macro
    if @macro.save
      redirect_to macros_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @macro
  end

  def update
    authorize @macro
    if @macro.update(macro_params)
      redirect_to macros_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @macro
    @macro.destroy
    redirect_to macros_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_macro
    @macro = Macro.find(params[:id])
  end

  def macro_params
    params.require(:macro).permit(:name, :body)
  end
end
