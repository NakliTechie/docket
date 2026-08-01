class StorageDeletionJob < ApplicationJob
  queue_as :default

  class CleanupError < StandardError; end

  retry_on CleanupError, wait: :polynomially_longer, attempts: 8 do |job, error|
    deletion = StorageDeletion.find_by(id: job.arguments.first)
    deletion&.update!(status: :failed, last_error: error.message.to_s.truncate(500))
  end

  def perform(deletion_id)
    deletion = StorageDeletion.find_by(id: deletion_id)
    return unless deletion&.status_pending?

    ActiveStorage::Blob.services.fetch(deletion.service_name).delete(deletion.blob_key)
    deletion.update!(status: :completed, completed_at: Time.current, last_error: nil)
  rescue StandardError => e
    deletion&.increment!(:attempts)
    deletion&.update_columns(last_error: e.message.to_s.truncate(500), updated_at: Time.current)
    raise CleanupError, e.message
  end
end
