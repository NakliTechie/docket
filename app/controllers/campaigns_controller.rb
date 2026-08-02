class CampaignsController < ApplicationController
  require_feature "crm"
  before_action :set_campaign, only: %i[show edit update destroy]

  def index
    authorize Campaign
    @campaigns = policy_scope(Campaign).order(created_at: :desc)
    @lead_counts = policy_scope(Lead).group(:first_touch_campaign_id).count
    @deal_counts = policy_scope(Deal).group(:first_touch_campaign_id).count
  end

  def show
    authorize @campaign
    @leads = policy_scope(Lead).where(first_touch_campaign: @campaign).order(created_at: :desc).limit(20)
    @deals = policy_scope(Deal).where(first_touch_campaign: @campaign).order(created_at: :desc).limit(20)
  end

  def new
    @campaign = Campaign.new(currency: "INR", starts_on: Date.current)
    authorize @campaign
  end

  def create
    @campaign = Campaign.new(campaign_params)
    authorize @campaign
    if @campaign.save
      redirect_to @campaign, notice: t(".created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @campaign
  end

  def update
    authorize @campaign
    if @campaign.update(campaign_params)
      redirect_to @campaign, notice: t(".updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @campaign
    @campaign.destroy
    redirect_to campaigns_path, notice: t(".deleted"), status: :see_other
  end

  private

  def set_campaign
    @campaign = policy_scope(Campaign).find(params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(
      :name, :code, :description, :status, :channel, :starts_on, :ends_on,
      :budget, :currency, :utm_source, :utm_medium, :utm_campaign
    )
  end
end
