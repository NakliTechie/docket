class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization
  include Pagy::Backend

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :set_request_context
  before_action :set_locale

  after_action :verify_pundit_compliance, unless: :skip_pundit?

  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from Case::InvalidTransition, with: :invalid_transition

  private

  # Pundit resolves the policy user from here (no current_user helper in
  # Rails 8 generated auth).
  def pundit_user
    Current.user
  end

  def set_request_context
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
  end

  def set_locale
    I18n.locale = session[:locale].presence || Current.user&.locale.presence || I18n.default_locale
  rescue I18n::InvalidLocale
    I18n.locale = I18n.default_locale
  end

  # Every action must either authorize a record or use a policy scope —
  # forgetting is a test failure, not a silent hole.
  def verify_pundit_compliance
    if action_name == "index"
      unless pundit_policy_scoped? || pundit_policy_authorized?
        raise Pundit::AuthorizationNotPerformedError, self.class.name
      end
    else
      verify_authorized
    end
  end

  # Auth endpoints (sessions, passwords) sit outside policy land.
  def skip_pundit?
    is_a?(SessionsController) || is_a?(PasswordsController)
  end

  def forbidden
    respond_to do |format|
      format.html { render "errors/forbidden", status: :forbidden }
      format.json { render json: { error: "forbidden" }, status: :forbidden }
    end
  end

  def invalid_transition(exception)
    redirect_back fallback_location: root_path, alert: t("cases.errors.invalid_transition")
  end
end
