module Api
  module V1
    class ProductsController < BaseController
      require_feature "crm"
      before_action :set_product, only: %i[show update destroy]

      def index
        records = api_scope(Product, scope: "crm:read").order(:name)
        render json: { data: records.map { |product| Serialize.product(product) } }
      end

      def show
        authorize_api!(@product, :show?, scope: "crm:read")
        render json: { data: Serialize.product(@product) }
      end

      def create
        product = Product.new(product_params)
        authorize_api!(product, :create?, scope: "crm:write")
        product.save ? render(json: { data: Serialize.product(product) }, status: :created) : render_validation_errors(product)
      end

      def update
        authorize_api!(@product, :update?, scope: "crm:write")
        @product.update(product_params) ? render(json: { data: Serialize.product(@product) }) : render_validation_errors(@product)
      end

      def destroy
        authorize_api!(@product, :destroy?, scope: "crm:write")
        @product.destroy ? head(:no_content) : render_validation_errors(@product)
      end

      private

      def set_product
        scope = action_name == "show" ? "crm:read" : "crm:write"
        @product = api_scope(Product, scope: scope).find(params[:id])
      end

      def product_params
        params.require(:product).permit(:name, :sku, :description, :default_unit_price,
                                        :currency, :active)
      end
    end
  end
end
