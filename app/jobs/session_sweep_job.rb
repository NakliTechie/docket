# Recurring sweep (config/recurring.yml): garbage-collects expired auth
# artifacts so their tables don't grow unbounded —
#   * sessions past their absolute/idle TTL (the live request path also
#     destroys one on resume, M5; this catches owners who never return);
#   * expired OAuth authorization codes, access tokens, and refresh tokens.
class SessionSweepJob < ApplicationJob
  queue_as :default

  def perform
    Session.expired.in_batches.delete_all
    OauthAuthorizationCode.expired.in_batches.delete_all
    OauthAccessToken.expired.in_batches.delete_all
    OauthRefreshToken.expired.in_batches.delete_all
    record_sweep_success!
  end
end
