module Api
  module V1
    class DealLineItemsController < BaseController
      require_feature "crm"
      before_action :set_item, only: %i[update destroy]

      def create
        deal = api_scope(Deal, scope: "crm:write").find(params[:deal_id])
        item = deal.deal_line_items.new(item_params.merge(currency: deal.currency))
        authorize_api!(item, :create?, scope: "crm:write")
        item.save ? render(json: { data: Serialize.deal_line_item(item) }, status: :created) : render_validation_errors(item)
      end

      def update
        authorize_api!(@item, :update?, scope: "crm:write")
        attributes = item_params.except(:product_id)
        @item.update(attributes) ? render(json: { data: Serialize.deal_line_item(@item) }) : render_validation_errors(@item)
      end

      def destroy
        authorize_api!(@item, :destroy?, scope: "crm:write")
        @item.destroy
        head :no_content
      end

      private

      def set_item
        @item = api_scope(DealLineItem, scope: "crm:write").find(params[:id])
      end

      def item_params
        params.require(:deal_line_item).permit(:product_id, :description, :quantity, :unit_price)
      end
    end
  end
end
