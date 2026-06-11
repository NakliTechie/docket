class Session < ApplicationRecord
  # A signed session cookie lives ~20 years (cookies.signed.permanent), so
  # without a server-side TTL a leaked cookie never stops working (M5).
  # Two ceilings, both enforced on every resume:
  #   ABSOLUTE_TIMEOUT — hard cap from login, re-auth required after.
  #   IDLE_TIMEOUT     — sliding window; a session unused this long dies.
  ABSOLUTE_TIMEOUT = 30.days
  IDLE_TIMEOUT = 12.hours
  # Don't write updated_at on every request — only once the row is this stale.
  TOUCH_INTERVAL = 5.minutes

  belongs_to :user

  scope :expired, -> {
    where("created_at < :abs OR updated_at < :idle", abs: ABSOLUTE_TIMEOUT.ago, idle: IDLE_TIMEOUT.ago)
  }

  def expired?
    created_at < ABSOLUTE_TIMEOUT.ago || updated_at < IDLE_TIMEOUT.ago
  end

  # Slide the idle window forward on activity, throttled to one write per
  # TOUCH_INTERVAL so an active session isn't a DB write per request.
  def touch_if_stale
    touch if updated_at < TOUCH_INTERVAL.ago
  end
end
