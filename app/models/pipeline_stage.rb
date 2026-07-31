# A column on the kanban board — one stage of a pipeline. Terminal
# stages flag won/lost, which derive a moved deal's status.
class PipelineStage < ApplicationRecord
  include SoftDeletable
  include Audited

  belongs_to :pipeline, -> { with_deleted }, inverse_of: :pipeline_stages
  has_many :deals, dependent: nil

  before_destroy :prevent_destroy_with_live_deals

  validates :name, presence: true
  validates :probability, numericality: { in: 0..100 }, allow_nil: true
  validate :won_xor_lost

  def terminal?
    is_won? || is_lost?
  end

  # The deal status implied by landing in this stage.
  def implied_status
    return :won if is_won?
    return :lost if is_lost?
    :open
  end

  private

  def prevent_destroy_with_live_deals
    return unless deals.exists?

    errors.add(:base, "move live deals to another stage before removing this stage")
    throw :abort
  end

  def won_xor_lost
    errors.add(:base, :won_and_lost) if is_won? && is_lost?
  end
end
