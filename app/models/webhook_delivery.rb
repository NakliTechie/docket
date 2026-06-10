class WebhookDelivery < ApplicationRecord
  belongs_to :webhook_endpoint

  enum :status, { pending: 0, delivered: 1, failed: 2 }, prefix: true

  validates :event, :payload, presence: true

  scope :recent_first, -> { order(id: :desc) }
end
