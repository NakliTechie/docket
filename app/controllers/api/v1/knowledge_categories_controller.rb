module Api
  module V1
    class KnowledgeCategoriesController < BaseController
      require_feature "service_desk.kb"
      before_action :set_category, only: %i[show update destroy]

      def index
        records = api_scope(KnowledgeCategory, scope: "config:read").order(:position, :name)
        render json: { data: records.map { |category| Serialize.knowledge_category(category) } }
      end

      def show
        authorize_api!(@knowledge_category, :show?, scope: "config:read")
        render json: { data: Serialize.knowledge_category(@knowledge_category) }
      end

      def create
        category = KnowledgeCategory.new(category_params)
        authorize_api!(category, :create?, scope: "config:write")
        if category.save
          render json: { data: Serialize.knowledge_category(category) }, status: :created
        else
          render_validation_errors(category)
        end
      end

      def update
        authorize_api!(@knowledge_category, :update?, scope: "config:write")
        if @knowledge_category.update(category_params)
          render json: { data: Serialize.knowledge_category(@knowledge_category) }
        else
          render_validation_errors(@knowledge_category)
        end
      end

      def destroy
        authorize_api!(@knowledge_category, :destroy?, scope: "config:write")
        detach_articles_and_destroy!
        head :no_content
      end

      private

      def set_category
        @knowledge_category = KnowledgeCategory.find(params[:id])
      end

      def category_params
        params.require(:knowledge_category).permit(:name, :description, :parent_id, :position)
      end

      def detach_articles_and_destroy!
        @knowledge_category.transaction do
          @knowledge_category.reference_docs.find_each { |doc| doc.update!(knowledge_category: nil) }
          @knowledge_category.destroy!
        end
      end
    end
  end
end
