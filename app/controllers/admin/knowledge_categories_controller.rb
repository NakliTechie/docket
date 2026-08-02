module Admin
  class KnowledgeCategoriesController < ApplicationController
    require_feature "service_desk.kb"
    before_action :set_category, only: %i[edit update destroy]
    before_action :set_parent_options, only: %i[new create edit update]

    def index
      authorize KnowledgeCategory
      @knowledge_categories = policy_scope(KnowledgeCategory).includes(:parent).to_a.sort_by(&:display_path)
    end

    def new
      @knowledge_category = KnowledgeCategory.new
      authorize @knowledge_category
    end

    def create
      @knowledge_category = KnowledgeCategory.new(category_params)
      authorize @knowledge_category
      if @knowledge_category.save
        redirect_to admin_knowledge_categories_path, notice: t(".created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @knowledge_category
    end

    def update
      authorize @knowledge_category
      if @knowledge_category.update(category_params)
        redirect_to admin_knowledge_categories_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @knowledge_category
      @knowledge_category.transaction do
        @knowledge_category.reference_docs.find_each { |doc| doc.update!(knowledge_category: nil) }
        @knowledge_category.destroy!
      end
      redirect_to admin_knowledge_categories_path, notice: t(".deleted"), status: :see_other
    end

    private

    def set_category
      @knowledge_category = KnowledgeCategory.find(params[:id])
    end

    def set_parent_options
      excluded_ids = @knowledge_category&.persisted? ? @knowledge_category.self_and_descendants.map(&:id) : []
      @parent_options = KnowledgeCategory.where.not(id: excluded_ids).to_a.sort_by(&:display_path)
    end

    def category_params
      params.require(:knowledge_category).permit(:name, :description, :parent_id, :position)
    end
  end
end
