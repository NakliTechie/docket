# Recurring sweep (config/recurring.yml): deletes sessions past their
# absolute or idle TTL so the table doesn't accumulate dead rows. The
# live request path also destroys an expired session on resume (M5); this
# just garbage-collects sessions whose owner never returns.
class SessionSweepJob < ApplicationJob
  queue_as :default

  def perform
    Session.expired.in_batches.delete_all
  end
end
