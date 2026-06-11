class ApplicationJob < ActiveJob::Base
  # Cases carry a lock_version (optimistic locking). A job that loaded a
  # case which a human then edited mid-flight hits StaleObjectError — just
  # re-run; ActiveJob reloads records by GlobalID, so the retry sees the
  # current row. The per-record work (breach flip, triage) is idempotent.
  retry_on ActiveRecord::StaleObjectError, wait: 1.second, attempts: 3
end
