module Api
  module V1
    class DealContactRolesController < BaseController
      require_feature "crm"
      before_action :set_link, only: %i[update destroy]

      def create
        deal = api_scope(Deal, scope: "crm:write").find(params[:deal_id])
        link = deal.deal_contact_roles.new(link_params)
        authorize_api!(link, :create?, scope: "crm:write")
        if link.save
          render json: { data: Serialize.deal_contact_role(link) }, status: :created
        else
          render_validation_errors(link)
        end
      end

      def update
        authorize_api!(@link, :update?, scope: "crm:write")
        if @link.update(link_params.except(:contact_id))
          render json: { data: Serialize.deal_contact_role(@link) }
        else
          render_validation_errors(@link)
        end
      end

      def destroy
        authorize_api!(@link, :destroy?, scope: "crm:write")
        @link.destroy
        head :no_content
      end

      private

      def set_link
        @link = api_scope(DealContactRole, scope: "crm:write").find(params[:id])
      end

      def link_params
        params.require(:deal_contact_role).permit(:contact_id, :role)
      end
    end
  end
end
