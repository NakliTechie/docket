# Durable after-commit ledger for Active Storage bytes whose database rows have
# already been removed. It deliberately has no Tenant foreign key: tenant purge
# must be able to retain and finish this cleanup after the tenant row is gone.
class StorageDeletion < ApplicationRecord
  enum :status, { pending: 0, completed: 1, failed: 2 }, prefix: true

  validates :owner_tenant_id, :service_name, :blob_key, presence: true
  validates :blob_key, uniqueness: true

  scope :due, -> { status_pending.order(:id) }
end
