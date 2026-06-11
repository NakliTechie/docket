# One sync attempt for a connector — the audit-friendly log the admin UI
# shows. Append-only in spirit (a run is written once when it finishes).
class ConnectorRun < ApplicationRecord
  belongs_to :connector

  enum :trigger, { manual: 0, scheduled: 1, webhook: 2 }, prefix: true
  enum :status, { running: 0, success: 1, failed: 2 }, prefix: true

  scope :recent_first, -> { order(id: :desc) }

  def duration_seconds
    return nil unless started_at && finished_at
    (finished_at - started_at).round(1)
  end
end
