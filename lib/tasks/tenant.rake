namespace :docket do
  namespace :tenant do
    desc "Export one suspended tenant's rows, attachments, and a checksummed manifest"
    task :export, %i[slug path] => :environment do |_task, args|
      tenant = Tenant.find_by!(slug: args.fetch(:slug))
      result = Tenants::Export.call(tenant: tenant, path: args[:path].presence)
      puts "Export complete: #{result.path}"
      puts "Receipt: #{result.receipt.id} (#{result.receipt.export_id})"
      puts "Manifest SHA-256: #{result.receipt.manifest_sha256}"
    end

    desc "Permanently purge a suspended tenant after a verified export receipt"
    task :purge, %i[slug receipt_id] => :environment do |_task, args|
      tenant = Tenant.find_by!(slug: args.fetch(:slug))
      receipt = ActsAsTenant.with_tenant(tenant) do
        TenantExportReceipt.find(args.fetch(:receipt_id))
      end
      confirmation = ENV["CONFIRM_TENANT_PURGE"]
      result = Tenants::Purge.call(tenant: tenant, receipt: receipt, confirmation: confirmation)
      puts "Purged tenant ##{result.tenant_id}: #{result.deleted_rows} rows, " \
           "#{result.deleted_blobs} blobs; retained #{result.audit_entries_retained} redacted audit entries."
    end
  end
end
