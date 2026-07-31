class WebhookDelivery < ApplicationRecord
  belongs_to :webhook_endpoint

  enum :status, { pending: 0, delivered: 1, failed: 2 }, prefix: true

  validates :event, :payload, presence: true

  scope :recent_first, -> { order(id: :desc) }

  after_create_commit :enqueue_delivery

  private

  def enqueue_delivery
    WebhookDeliveryJob.perform_later(self)
  rescue ActiveJob::EnqueueError => e
    Rails.logger.warn("could not enqueue webhook delivery #{id}: #{e.message}")
  end
end
