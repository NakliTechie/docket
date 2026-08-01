class SlaClockEvent < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  enum :clock_kind, { first_response: 0, resolution: 1 }, prefix: true
  enum :event_kind, {
    started: 0, paused: 1, resumed: 2, stopped: 3, recalculated: 4, breached: 5
  }, prefix: true

  belongs_to :case, -> { with_deleted }

  validates :clock_kind, :event_kind, :occurred_at, presence: true
  validates :remaining_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                                allow_nil: true

  def readonly? = persisted?

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "SLA clock events are append-only" }
end
