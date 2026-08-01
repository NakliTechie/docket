module Api
  module V1
    class LeadCaptureFormsController < BaseController
      require_feature "crm"
      before_action :set_form, only: %i[show update destroy]

      def index
        records = api_scope(LeadCaptureForm, scope: "crm:write").order(:name)
        render json: { data: records.map { |form| Serialize.lead_capture_form(form) } }
      end

      def show
        authorize_api!(@form, :show?, scope: "crm:write")
        render json: { data: Serialize.lead_capture_form(@form) }
      end

      def create
        form = LeadCaptureForm.new(form_params)
        authorize_api!(form, :create?, scope: "crm:write")
        if form.save
          render json: { data: Serialize.lead_capture_form(form) }, status: :created
        else
          render_validation_errors(form)
        end
      end

      def update
        authorize_api!(@form, :update?, scope: "crm:write")
        if @form.update(form_params)
          render json: { data: Serialize.lead_capture_form(@form) }
        else
          render_validation_errors(@form)
        end
      end

      def destroy
        authorize_api!(@form, :destroy?, scope: "crm:write")
        @form.destroy
        head :no_content
      end

      private

      def set_form
        @form = api_scope(LeadCaptureForm, scope: "crm:write").find(params[:id])
      end

      def form_params
        params.require(:lead_capture_form).permit(:name, :slug, :consent_disclosure,
                                                  :active, :is_default, field_mapping: {})
      end
    end
  end
end
