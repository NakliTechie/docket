class ProductsController < ApplicationController
  require_feature "crm"
  before_action :set_product, only: %i[edit update destroy]

  def index
    authorize Product
    @products = policy_scope(Product).order(:name)
  end

  def new
    @product = Product.new
    authorize @product
  end

  def create
    @product = Product.new(product_params)
    authorize @product
    if @product.save
      redirect_to products_path, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @product
  end

  def update
    authorize @product
    if @product.update(product_params)
      redirect_to products_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @product
    if @product.destroy
      redirect_to products_path, notice: t(".deleted"), status: :see_other
    else
      redirect_to products_path, alert: @product.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def set_product
    @product = policy_scope(Product).find(params[:id])
  end

  def product_params
    params.require(:product).permit(:name, :sku, :description, :default_unit_price,
                                    :currency, :active)
  end
end
