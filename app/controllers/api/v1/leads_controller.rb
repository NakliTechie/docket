module Api
  module V1
    class LeadsController < BaseController
      require_feature "crm"
      before_action :set_lead, only: %i[show update destroy convert merge]

      def index
        scope = api_scope(Lead, scope: "crm:read").canonical.search(params[:q])
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(owner_id: params[:owner_id]) if params[:owner_id].present?
        pagy, records = pagy(scope.order(created_at: :desc))
        render json: { data: records.map { |l| Serialize.lead(l) }, pagination: pagination_meta(pagy) }
      end

      def show
        authorize_api!(@lead, :show?, scope: "crm:read")
        render json: { data: Serialize.lead(@lead) }
      end

      def create
        authorize_api!(Lead.new, :create?, scope: "crm:write")
        attrs = lead_params
        lead = Lead.new(attrs)
        lead.source = :api unless attrs.key?(:source) # API-sourced unless stated
        if lead.save
          render json: { data: Serialize.lead(lead) }, status: :created
        else
          render_validation_errors(lead)
        end
      end

      def update
        authorize_api!(@lead, :update?, scope: "crm:write")
        attributes = lead_params
        custom_fields = attributes.delete(:custom_fields)
        @lead.assign_attributes(attributes)
        @lead.assign_custom_fields(custom_fields) if custom_fields
        if @lead.save
          render json: { data: Serialize.lead(@lead) }
        else
          render_validation_errors(@lead)
        end
      end

      def destroy
        authorize_api!(@lead, :destroy?, scope: "crm:write")
        @lead.destroy
        head :no_content
      end

      def convert
        authorize_api!(@lead, :convert?, scope: "crm:write")
        contact = @lead.convert!
        render json: { data: Serialize.lead(@lead.reload), contact: Serialize.contact(contact) }
      end

      def merge
        authorize_api!(@lead, :merge?, scope: "crm:write")
        source = api_scope(Lead, scope: "crm:write").canonical.find(params.require(:source_lead_id))
        authorize_api!(source, :merge?, scope: "crm:write")
        LeadMerge.call(source: source, target: @lead, actor: Current.actor)
        render json: { data: Serialize.lead(@lead.reload) }
      rescue LeadMerge::Error => error
        render_error("invalid_merge", detail: error.message, status: :unprocessable_entity)
      end

      private

      def set_lead
        @lead = Lead.find(params[:id]).canonical_record
      end

      def lead_params
        params.require(:lead).permit(:name, :email, :phone, :company_name,
                                     :source, :owner_id, :value_estimate_cents, :notes,
                                     :sms_consent, :email_consent, :first_touch_campaign_id,
                                     custom_fields: {})
      end
    end
  end
end
