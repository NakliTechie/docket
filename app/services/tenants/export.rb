require "fileutils"

module Tenants
  class Export
    Result = Data.define(:receipt, :path, :manifest)

    def self.call(...) = new(...).call

    def initialize(tenant:, path: nil)
      @tenant = tenant
      timestamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
      @export_id = "tenant-export-#{tenant.slug}-#{timestamp}-#{SecureRandom.hex(4)}"
      @path = Pathname(path || Rails.root.join("storage/exports", @export_id)).expand_path
    end

    def call
      raise ArgumentError, "tenant must be suspended before export" unless @tenant.suspended?
      raise ArgumentError, "export destination already exists: #{@path}" if @path.exist?

      partial = Pathname("#{@path}.partial-#{SecureRandom.hex(4)}")
      receipt = manifest = nil
      transaction_options = ApplicationRecord.connection.adapter_name == "PostgreSQL" ? { isolation: :repeatable_read } : {}
      ApplicationRecord.transaction(**transaction_options) do
        @tenant.lock!
        raise ArgumentError, "tenant must remain suspended during export" unless @tenant.suspended?

        FileUtils.mkdir_p(partial.join("data"), mode: 0o700)
        inventory = DataInventory.new(@tenant)
        inventory_sha256 = inventory.state_sha256
        files = export_rows(partial, inventory)
        operational = OperationalInventory.new(@tenant)
        files.concat(export_operational_rows(partial, operational))
        attachments = export_attachments(partial, inventory, files)
        manifest = build_manifest(inventory, operational, files, attachments, inventory_sha256)
        manifest_path = partial.join("manifest.json")
        File.write(manifest_path, JSON.pretty_generate(manifest), mode: "wb", perm: 0o600)
        FileUtils.mkdir_p(@path.dirname, mode: 0o700)
        FileUtils.mv(partial, @path)

        receipt = ActsAsTenant.with_tenant(@tenant) do
          TenantExportReceipt.create!(
            export_id: @export_id, export_path: @path.to_s,
            manifest_sha256: Digest::SHA256.file(@path.join("manifest.json")).hexdigest,
            inventory_sha256: inventory_sha256,
            row_counts: inventory.counts, attachment_count: attachments.size,
            completed_at: Time.current
          )
        end
      end
      Result.new(receipt: receipt, path: @path, manifest: manifest)
    rescue StandardError
      FileUtils.remove_entry(partial) if partial&.exist?
      FileUtils.remove_entry(@path) if @path.exist? && receipt.nil?
      raise
    end

    private

    def export_rows(root, inventory)
      inventory.tables.each_with_object([]) do |table, files|
        rows = inventory.rows(table)
        next if rows.empty?

        relative = Pathname("data/#{table}.jsonl")
        target = root.join(relative)
        File.open(target, "wb", 0o600) do |io|
          rows.each { |row| io.write(JSON.generate(row) << "\n") }
        end
        files << file_entry(root, relative, kind: "table", rows: rows.size)
      end
    end

    def export_attachments(root, inventory, files)
      inventory.attachment_rows.filter_map do |row|
        blob = ActiveStorage::Blob.find_by(id: row.fetch("blob_id"))
        next unless blob

        filename = blob.filename.to_s.gsub(/[^a-zA-Z0-9._-]/, "_").presence || "attachment"
        relative = Pathname("attachments/#{row.fetch('id')}/#{filename}")
        target = root.join(relative)
        FileUtils.mkdir_p(target.dirname)
        File.open(target, "wb", 0o600) { |io| blob.download { |chunk| io.write(chunk) } }
        entry = file_entry(root, relative, kind: "attachment")
        entry.merge!(
          attachment_id: row.fetch("id"), blob_id: blob.id,
          record_type: row.fetch("record_type"), record_id: row.fetch("record_id"),
          content_type: blob.content_type, filename: blob.filename.to_s
        )
        files << entry
        entry
      end
    end

    def export_operational_rows(root, operational)
      operational.rows.each_with_object([]) do |(name, rows), files|
        next if rows.empty?

        relative = Pathname("operational/#{name}.jsonl")
        target = root.join(relative)
        FileUtils.mkdir_p(target.dirname, mode: 0o700)
        File.open(target, "wb", 0o600) { |io| rows.each { |row| io.write(JSON.generate(row) << "\n") } }
        files << file_entry(root, relative, kind: "operational", rows: rows.size)
      end
    end

    def file_entry(root, relative, kind:, rows: nil)
      target = root.join(relative)
      { path: relative.to_s, kind: kind, bytes: target.size,
        sha256: Digest::SHA256.file(target).hexdigest, rows: rows }.compact
    end

    def build_manifest(inventory, operational, files, attachments, inventory_sha256)
      chain = AuditEntry.verify_chain(cache: false, checkpoint: false)
      {
        format: "docket-tenant-export-v1", export_id: @export_id,
        tenant: { id: @tenant.id, slug: @tenant.slug, name: @tenant.name },
        exported_at: Time.current.utc.iso8601(6), schema_version: ActiveRecord::Migrator.current_version,
        row_counts: inventory.counts, attachment_count: attachments.size,
        operational_counts: operational.counts,
        inventory_sha256: inventory_sha256,
        audit_chain: chain.slice(:ok, :count, :head_id, :head_sha),
        encrypted_fields: "ciphertext; restore requires a readable Docket vault keyring",
        files: files
      }
    end
  end
end
