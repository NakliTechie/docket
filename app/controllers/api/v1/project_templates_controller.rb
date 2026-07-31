module Api
  module V1
    class ProjectTemplatesController < BaseController
      require_feature "work"
      before_action :set_template, only: %i[show update destroy]

      def index
        records = api_scope(ProjectTemplate, scope: "work:manage").includes(:project_template_items).order(:name)
        render json: { data: records.map { |template| Serialize.project_template(template) } }
      end

      def show
        authorize_api!(@template, :show?, scope: "work:manage")
        render json: { data: Serialize.project_template(@template) }
      end

      def create
        template = ProjectTemplate.new(template_params)
        authorize_api!(template, :create?, scope: "work:manage")
        if template.save
          render json: { data: Serialize.project_template(template) }, status: :created
        else
          render_validation_errors(template)
        end
      end

      def update
        authorize_api!(@template, :update?, scope: "work:manage")
        if @template.update(template_params)
          render json: { data: Serialize.project_template(@template) }
        else
          render_validation_errors(@template)
        end
      end

      def destroy
        authorize_api!(@template, :destroy?, scope: "work:manage")
        @template.destroy
        head :no_content
      end

      private

      def set_template
        @template = api_scope(ProjectTemplate, scope: "work:manage").find(params[:id])
      end

      def template_params
        params.require(:project_template).permit(
          :name, :key_prefix, :description, :active,
          project_template_items_attributes: %i[id title description kind priority estimate due_offset_days position _destroy]
        )
      end
    end
  end
end
