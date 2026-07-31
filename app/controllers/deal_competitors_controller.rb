class DealCompetitorsController < ApplicationController
  require_feature "crm"
  before_action :set_deal, only: :create
  before_action :set_link, only: %i[update destroy]

  def create
    @link = @deal.deal_competitors.new(link_params)
    authorize @link
    if @link.save
      redirect_to deal_path(@deal), notice: t(".created")
    else
      redirect_to deal_path(@deal), alert: @link.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  def update
    authorize @link
    if @link.update(link_params.except(:competitor_id))
      redirect_to deal_path(@link.deal), notice: t(".updated")
    else
      redirect_to deal_path(@link.deal), alert: @link.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  def destroy
    authorize @link
    deal = @link.deal
    @link.destroy
    redirect_to deal_path(deal), notice: t(".deleted"), status: :see_other
  end

  private

  def set_deal
    @deal = policy_scope(Deal).find(params[:deal_id])
  end

  def set_link
    @link = policy_scope(DealCompetitor).find(params[:id])
  end

  def link_params
    params.require(:deal_competitor).permit(:competitor_id, :disposition, :notes)
  end
end
