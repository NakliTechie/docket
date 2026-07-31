class SetupsController < ApplicationController
  STEP_SETTINGS = {
    "modules" => "setup_modules_confirmed",
    "email" => "setup_email_skipped",
    "team" => "setup_team_skipped"
  }.freeze

  def show
    authorize :settings, policy_class: PlatformAreaPolicy
    @setup = SetupProgress.new(actor: Current.user, base_url: request.base_url)
    @setup.mark_started!
  end

  def update
    authorize :settings, policy_class: PlatformAreaPolicy
    @setup = SetupProgress.new(actor: Current.user, base_url: request.base_url)
    @setup.mark_started!

    case params.require(:step)
    when "brand"
      brand_name = params.require(:brand_name).to_s.strip
      raise ActionController::BadRequest, "brand name is required" if brand_name.blank?

      Setting.set("brand_name", brand_name)
      redirect_to setup_path, notice: t(".updated")
    when "finish"
      @setup.finish!
      redirect_to root_path, notice: t(".finished")
    else
      setting = STEP_SETTINGS[params[:step]]
      raise ActionController::BadRequest, "unknown setup step" unless setting

      Setting.set(setting, true)
      redirect_to setup_path, notice: t(".updated")
    end
  rescue ArgumentError
    raise ActionController::BadRequest, "setup is not complete"
  end
end
