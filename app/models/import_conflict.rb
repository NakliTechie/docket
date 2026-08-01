class ImportConflict < ApplicationRecord
  acts_as_tenant(:tenant)

  STATUSES = %w[unresolved kept_local accepted_source resolved_manually].freeze

  belongs_to :import_run
  belongs_to :import_identity, optional: true
  belongs_to :target, polymorphic: true, optional: true

  validates :source_type, :external_id, :field, presence: true
  validates :status, inclusion: { in: STATUSES }
end
