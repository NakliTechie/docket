# No destructive deletes on audited models (handoff §6): destroy is a
# soft-delete that stamps +deleted_at+. Default scope hides deleted rows;
# use +with_deleted+ / +only_deleted+ to reach them.
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    default_scope { where(deleted_at: nil) }
    scope :with_deleted, -> { unscope(where: :deleted_at) }
    scope :only_deleted, -> { with_deleted.where.not(deleted_at: nil) }
  end

  def destroy
    return self if deleted?
    run_callbacks(:destroy) { update_columns(deleted_at: Time.current) && self }
  end

  def destroy!
    destroy || raise(ActiveRecord::RecordNotDestroyed.new("Failed to soft-delete the record", self))
  end

  def deleted?
    deleted_at.present?
  end

  # Clear deleted_at through a normal update so the Audited callback records
  # the restore (update_columns would silently bypass the audit chain).
  def restore!
    update!(deleted_at: nil)
    self
  end
end
