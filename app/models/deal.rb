# A sales opportunity moving through a pipeline's stages on the kanban
# board (v1.2 CRM). Moving a card = changing pipeline_stage; landing in a
# terminal stage derives won/lost.
class Deal < ApplicationRecord
  include SoftDeletable
  include Audited
  include HumanEnums

  humanizes_enums :status, :lost_reason

  enum :status, { open: 0, won: 1, lost: 2 }, default: :open, prefix: true
  # Why a deal was lost — captured when it lands in a lost stage, so the
  # sales report can break losses down. Nil until set; cleared if the deal
  # leaves the lost state (see #derive_status_from_stage).
  enum :lost_reason, { price: 0, competitor: 1, no_budget: 2, no_decision: 3, timing: 4, other: 5 },
       prefix: :lost_reason

  belongs_to :pipeline, -> { with_deleted }
  belongs_to :pipeline_stage, -> { with_deleted }
  belongs_to :owner, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :contact, -> { with_deleted }, optional: true
  belongs_to :organisation, -> { with_deleted }, optional: true
  belongs_to :lead, -> { with_deleted }, optional: true

  validates :name, presence: true
  validate :stage_belongs_to_pipeline

  before_validation :apply_default_pipeline, on: :create
  before_save :derive_status_from_stage, if: :will_save_change_to_pipeline_stage_id?

  scope :open_deals, -> { where(status: :open) }

  # The UI works in whole currency units; the column stores cents.
  def value
    value_cents && value_cents / 100.0
  end

  def value=(amount)
    self.value_cents = amount.present? ? (amount.to_f * 100).round : nil
  end

  # Move the card to another stage (the kanban drag). Validates the stage
  # is in this deal's pipeline; status is derived in a before_save.
  def move_to_stage!(stage)
    update!(pipeline_stage: stage)
  end

  private

  def apply_default_pipeline
    self.pipeline ||= Pipeline.default
    self.pipeline_stage ||= pipeline&.first_stage
  end

  def derive_status_from_stage
    implied = pipeline_stage&.implied_status || :open
    self.status = implied
    self.closed_at = implied == :open ? nil : (closed_at || Time.current)
    self.lost_reason = nil unless implied == :lost
  end

  def stage_belongs_to_pipeline
    return if pipeline_stage.nil? || pipeline.nil?
    errors.add(:pipeline_stage, :not_in_pipeline) if pipeline_stage.pipeline_id != pipeline_id
  end
end
