class SetupsController < ApplicationController
  STEP_SETTINGS = {
    "modules" => "setup_modules_confirmed",
    "email" => "setup_email_skipped",
    "team" => "setup_team_skipped"
  }.freeze

  def show
    authorize :settings, policy_class: PlatformAreaPolicy
    @setup = SetupProgress.new(actor: Current.user, base_url: request.base_url)
  end

  def update
    authorize :settings, policy_class: PlatformAreaPolicy
    setting = STEP_SETTINGS[params.require(:step)]
    raise ActionController::BadRequest, "unknown setup step" unless setting

    Setting.set(setting, true)
    redirect_to setup_path, notice: t(".updated")
  end
end
