class StorageDeletionSweepJob < ApplicationJob
  queue_as :default

  def perform
    StorageDeletion.due.limit(500).pluck(:id).each { |id| StorageDeletionJob.perform_later(id) }
    record_sweep_success!
  end
end
