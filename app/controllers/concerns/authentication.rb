module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      return unless cookies.signed[:session_id]
      session = Session.find_by(id: cookies.signed[:session_id])
      return unless session&.user&.active?

      # Enforce the server-side TTL: an expired session is destroyed so a
      # stale/leaked cookie can't be reused (M5).
      if session.expired?
        session.destroy
        cookies.delete(:session_id)
        return
      end
      session.touch_if_stale
      session
    end

    def request_authentication
      # Only bounce back to a GET/HEAD url — storing a POST/PATCH/DELETE one
      # would redirect (always GET) to a route that doesn't answer GET → 404.
      session[:return_to_after_authenticating] = request.url if request.get? || request.head?
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      # Rotate the Rails session on privilege change to defend against
      # session fixation, preserving the few keys that must survive login.
      preserved = session.to_hash.slice("return_to_after_authenticating", "locale")
      reset_session
      preserved.each { |k, v| session[k] = v }

      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session_record|
        Current.session = session_record
        cookies.signed.permanent[:session_id] = { value: session_record.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
