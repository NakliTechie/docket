module Admin
  # Read-only failed/throttled-login trail (the SecurityEvent log).
  class SecurityEventsController < ApplicationController
    def index
      authorize :security_event, policy_class: AdminAreaPolicy
      @pagy, @events = pagy(SecurityEvent.visible_to(Current.user).recent_first)
    end
  end
end
