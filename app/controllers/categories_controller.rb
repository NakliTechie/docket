class CategoriesController < ApplicationController
  before_action :set_category, only: %i[edit update destroy]

  def index
    @categories = policy_scope(Category).order(:name)
  end

  def new
    @category = Category.new
    authorize @category
  end

  def create
    @category = Category.new(category_params)
    authorize @category
    if @category.save
      redirect_to categories_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @category
  end

  def update
    authorize @category
    if @category.update(category_params)
      redirect_to categories_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @category
    @category.destroy
    redirect_to categories_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_category
    @category = Category.find(params[:id])
  end

  def category_params
    # ai_auto_resolve is deliberately excluded here: flipping the
    # autonomous-resolve gate is a separate, explicit admin action (G3).
    params.require(:category).permit(:name, :description)
  end
end
