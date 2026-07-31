class DealLineItemsController < ApplicationController
  require_feature "crm"
  before_action :set_deal, only: :create
  before_action :set_line_item, only: %i[update destroy]

  def create
    @line_item = @deal.deal_line_items.new(line_item_params.merge(currency: @deal.currency))
    authorize @line_item
    if @line_item.save
      redirect_to deal_path(@deal), notice: t(".created")
    else
      redirect_to deal_path(@deal), alert: @line_item.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  def update
    authorize @line_item
    if @line_item.update(line_item_params.except(:product_id))
      redirect_to deal_path(@line_item.deal), notice: t(".updated")
    else
      redirect_to deal_path(@line_item.deal), alert: @line_item.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  def destroy
    authorize @line_item
    deal = @line_item.deal
    @line_item.destroy
    redirect_to deal_path(deal), notice: t(".deleted"), status: :see_other
  end

  private

  def set_deal
    @deal = policy_scope(Deal).find(params[:deal_id])
  end

  def set_line_item
    @line_item = policy_scope(DealLineItem).find(params[:id])
  end

  def line_item_params
    params.require(:deal_line_item).permit(:product_id, :description, :quantity, :unit_price)
  end
end
