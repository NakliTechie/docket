module Api
  module V1
    class CategoriesController < BaseController
      before_action :set_category, only: %i[show update destroy]

      def index
        records = api_scope(Category, scope: "config:read").order(:name)
        render json: { data: records.map { |c| Serialize.category(c) } }
      end

      def show
        authorize_api!(@category, :show?, scope: "config:read")
        render json: { data: Serialize.category(@category) }
      end

      def create
        authorize_api!(Category.new, :create?, scope: "config:write")
        category = Category.new(category_params)
        if category.save
          render json: { data: Serialize.category(category) }, status: :created
        else
          render_validation_errors(category)
        end
      end

      def update
        authorize_api!(@category, :update?, scope: "config:write")
        if @category.update(category_params)
          render json: { data: Serialize.category(@category) }
        else
          render_validation_errors(@category)
        end
      end

      def destroy
        authorize_api!(@category, :destroy?, scope: "config:write")
        @category.destroy
        head :no_content
      end

      # AI auto-resolve stays a deliberate, admin-only act — human
      # tokens only, mirroring the console (handoff §4).
      def toggle_auto_resolve
        authorize_api!(@category = Category.find(params[:id]), :toggle_auto_resolve?, scope: nil)
        @category.update!(ai_auto_resolve: !@category.ai_auto_resolve)
        render json: { data: Serialize.category(@category) }
      end

      private

      def set_category
        @category = Category.find(params[:id])
      end

      def category_params
        params.require(:category).permit(:name, :description)
      end
    end
  end
end
