class ImportRun < ApplicationRecord
  acts_as_tenant(:tenant)

  STATUSES = %w[running completed completed_with_errors failed cancelled].freeze

  has_many :import_identities, foreign_key: :last_seen_run_id, dependent: :nullify,
           inverse_of: :last_seen_run
  has_many :import_conflicts, dependent: :destroy

  validates :source, :source_instance, :resume_token, :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :resume_token, uniqueness: true

  scope :completed, -> { where(status: %w[completed completed_with_errors]) }
  scope :clean_applied, -> { where(status: "completed", dry_run: false) }

  before_validation :initialize_operation, on: :create

  def self.latest_watermark(source:, source_instance: "default")
    clean_applied.where(source: source, source_instance: source_instance)
                 .where.not(watermark: nil).maximum(:watermark)
  end

  def finish!(result)
    update!(
      status: result.errors.any? ? "completed_with_errors" : "completed",
      stats: result.counts,
      unmapped: result.serialized_unmapped,
      error_messages: result.errors,
      conflicts: result.conflicts,
      watermark: result.watermark,
      completed_at: Time.current
    )
  end

  def fail!(error)
    update!(status: "failed",
            error_messages: Array(error_messages) << "#{error.class}: #{error.message}",
            completed_at: Time.current)
  end

  private

  def initialize_operation
    self.resume_token ||= SecureRandom.urlsafe_base64(24)
    self.started_at ||= Time.current
    self.checkpoint ||= {}
    self.stats ||= {}
    self.unmapped ||= {}
    self.error_messages ||= []
    self.conflicts ||= []
    self.options ||= {}
  end
end
