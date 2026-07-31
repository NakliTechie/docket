module Tenants
  class Purge
    class Error < StandardError; end
    Result = Data.define(:tenant_id, :deleted_rows, :deleted_blobs, :audit_entries_retained)

    def self.call(...) = new(...).call

    def initialize(tenant:, receipt:, confirmation:)
      @tenant = tenant
      @receipt = receipt
      @confirmation = confirmation.to_s
      @connection = ApplicationRecord.connection
    end

    def call
      validate!
      OperationalInventory.new(@tenant).purge!
      inventory = DataInventory.new(@tenant)
      attachment_ids = inventory.attachment_rows.map { |row| row.fetch("id") }
      exclusive_blobs = exclusive_blobs_for(attachment_ids)
      deleted_rows = inventory.counts.values.sum
      retained_audits = 0
      storage_deletion_ids = []

      ApplicationRecord.transaction do
        @tenant.lock!
        raise Error, "tenant changed after export; create a new export" unless @receipt.current_inventory?

        ActsAsTenant.with_tenant(@tenant) do
          final_event = AuditEntry.append!(
            action: "tenant.purge_authorized", auditable: @tenant,
            metadata: { export_id: @receipt.export_id,
                        manifest_sha256: @receipt.manifest_sha256 }, actor: Current.effective_actor
          )
          candidates = AuditEntry.where(tenant_id: @tenant.id).where.not(id: final_event.id)
          Privacy::AuditRedactor.call(
            entries: candidates, subject_token: "tenant:#{@tenant.id}:#{@receipt.export_id}",
            reason: "tenant_purge"
          )
          retained_audits = AuditEntry.where(tenant_id: @tenant.id).count
          # tenant_id is a denormalized filter and is deliberately outside the
          # canonical hash. Actor attribution is canonical and must remain
          # untouched so retained proof/final events keep the global chain valid.
          AuditEntry.where(tenant_id: @tenant.id).update_all(tenant_id: nil)

          storage_deletion_ids = exclusive_blobs.map do |blob|
            StorageDeletion.create!(owner_tenant_id: @tenant.id, service_name: blob.service_name,
                                    blob_key: blob.key).id
          end
          ActiveStorage::VariantRecord.where(blob_id: exclusive_blobs.map(&:id)).delete_all
          delete_inventory!(inventory)
          ActiveStorage::Blob.where(id: exclusive_blobs.map(&:id)).delete_all
          @tenant.delete
        end
      end

      storage_deletion_ids.each { |id| StorageDeletionJob.perform_later(id) }

      residue = DataInventory.new(@tenant.id).counts
      raise Error, "tenant purge left residue: #{residue.inspect}" if residue.any?

      Result.new(tenant_id: @tenant.id, deleted_rows: deleted_rows,
                 deleted_blobs: exclusive_blobs.size,
                 audit_entries_retained: retained_audits)
    end

    private

    def validate!
      raise Error, "the primary tenant cannot be purged" if @tenant.slug == Tenant::PRIMARY_SLUG
      raise Error, "tenant must be suspended before purge" unless @tenant.suspended?
      raise Error, "export receipt belongs to another tenant" unless @receipt.tenant_id == @tenant.id
      raise Error, "export archive or manifest digest is invalid" unless @receipt.archive_intact?
      raise Error, "tenant changed after export; create a new export" unless @receipt.current_inventory?
      expected = "PURGE #{@tenant.slug} #{@receipt.export_id}"
      raise Error, "confirmation must equal #{expected.inspect}" unless @confirmation == expected
    end

    def exclusive_blobs_for(attachment_ids)
      return [] if attachment_ids.empty?

      blob_ids = ActiveStorage::Attachment.where(id: attachment_ids).distinct.pluck(:blob_id)
      ActiveStorage::Blob.where(id: blob_ids).select do |blob|
        blob.attachments.where.not(id: attachment_ids).none?
      end
    end

    def delete_inventory!(inventory)
      inventory.deletion_order.each do |table|
        ids = inventory.owned_ids.fetch(table, [])
        next if ids.empty?

        relation = Arel::Table.new(table)
        deletion = Arel::DeleteManager.new(relation)
        deletion.where(relation[@connection.primary_key(table)].in(ids))
        @connection.delete(deletion)
      end
    end
  end
end
