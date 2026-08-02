module Api
  module V1
    class ReferenceDocsController < BaseController
      require_feature "service_desk.kb"
      before_action :set_doc, only: %i[show update destroy versions publish retire]

      def index
        records = api_scope(ReferenceDoc, scope: "config:read").order(:title)
        render json: { data: records.map { |d| Serialize.reference_doc(d) } }
      end

      def show
        authorize_api!(@reference_doc, :show?, scope: "config:read")
        render json: { data: Serialize.reference_doc(@reference_doc) }
      end

      def create
        authorize_api!(ReferenceDoc.new, :create?, scope: "config:write")
        doc = ReferenceDoc.new(doc_params)
        if doc.save
          render json: { data: Serialize.reference_doc(doc) }, status: :created
        else
          render_validation_errors(doc)
        end
      end

      def update
        authorize_api!(@reference_doc, :update?, scope: "config:write")
        if @reference_doc.update(doc_params)
          render json: { data: Serialize.reference_doc(@reference_doc) }
        else
          render_validation_errors(@reference_doc)
        end
      end

      def destroy
        authorize_api!(@reference_doc, :destroy?, scope: "config:write")
        @reference_doc.destroy
        head :no_content
      end

      def versions
        authorize_api!(@reference_doc, :show?, scope: "config:read")
        render json: { data: @reference_doc.reference_doc_versions.map { |version| Serialize.reference_doc_version(version) } }
      end

      def publish
        change_status!(:published)
      end

      def retire
        change_status!(:retired)
      end

      private

      def set_doc
        @reference_doc = ReferenceDoc.find(params[:id])
      end

      def doc_params
        params.require(:reference_doc).permit(
          :title, :body, :status, :visibility, :locale, :translation_key,
          :knowledge_category_id, :category_id
        )
      end

      def change_status!(status)
        authorize_api!(@reference_doc, :update?, scope: "config:write")
        if @reference_doc.update(status: status)
          render json: { data: Serialize.reference_doc(@reference_doc) }
        else
          render_validation_errors(@reference_doc)
        end
      end
    end
  end
end
