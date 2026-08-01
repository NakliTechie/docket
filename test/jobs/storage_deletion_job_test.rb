require "test_helper"

class StorageDeletionJobTest < ActiveJob::TestCase
  test "deletes storage bytes before completing the durable ledger row" do
    service = ActiveStorage::Blob.service
    key = "storage-deletion-test-#{SecureRandom.hex(8)}"
    service.upload(key, StringIO.new("private bytes"))
    deletion = StorageDeletion.create!(owner_tenant_id: tenants(:primary).id,
                                        service_name: service.name, blob_key: key)

    assert service.exist?(key)

    StorageDeletionJob.perform_now(deletion.id)

    assert_not service.exist?(key)
    assert deletion.reload.status_completed?
    assert deletion.completed_at.present?
    assert_equal 0, deletion.attempts
  ensure
    service&.delete(key) if key
  end

  test "a repeated delivery is harmless after the ledger is complete" do
    service = ActiveStorage::Blob.service
    deletion = StorageDeletion.create!(owner_tenant_id: tenants(:primary).id,
                                        service_name: service.name,
                                        blob_key: "already-cleaned-#{SecureRandom.hex(8)}",
                                        status: :completed, completed_at: Time.current)

    assert_no_changes -> { deletion.reload.updated_at } do
      StorageDeletionJob.perform_now(deletion.id)
    end
  end
end
