require "test_helper"
require "tmpdir"

class TenantPurgeTest < ActiveSupport::TestCase
  test "requires a suspended tenant, intact receipt, and exact confirmation" do
    tenant = tenants(:acme)
    tenant.suspended!
    Dir.mktmpdir("docket-purge-guard") do |dir|
      export = Tenants::Export.call(tenant: tenant, path: File.join(dir, "archive"))

      assert_raises(Tenants::Purge::Error) do
        Tenants::Purge.call(tenant: tenant, receipt: export.receipt, confirmation: "wrong")
      end
      assert_raises(Tenants::Purge::Error) do
        Tenants::Purge.call(tenant: tenant, receipt: export.receipt, confirmation: "wrong")
      end

      exported_path = JSON.parse(export.path.join("manifest.json").read).fetch("files").first.fetch("path")
      exported_data = export.path.join(exported_path)
      exported_data.open("ab") { |file| file.write("tampered") }
      refute export.receipt.archive_intact?
      assert_raises(Tenants::Purge::Error) do
        Tenants::Purge.call(
          tenant: tenant, receipt: export.receipt,
          confirmation: "PURGE #{tenant.slug} #{export.receipt.export_id}"
        )
      end
    end
  end

  test "purges the reflected tenant graph and exclusive blobs while retaining a valid redacted audit chain" do
    tenant = tenants(:acme)
    tenant.suspended!
    blob_id = nil
    ActsAsTenant.with_tenant(tenant) do
      actor = User.create!(name: "Acme Purge Operator", email_address: "purger@acme.test",
                           password: "long-enough-password", role: :client_admin)
      Current.actor = actor
      contact = Contact.create!(name: "Purge Me", email: "purge@acme.test")
      kase = Case.create!(subject: "Purge case", contact: contact)
      kase.files.attach(io: StringIO.new("purge blob"), filename: "purge.txt",
                        content_type: "text/plain")
      blob_id = kase.files.first.blob_id
    end

    Dir.mktmpdir("docket-purge-test") do |dir|
      export = Tenants::Export.call(tenant: tenant, path: File.join(dir, "archive"))
      confirmation = "PURGE #{tenant.slug} #{export.receipt.export_id}"

      result = Tenants::Purge.call(tenant: tenant, receipt: export.receipt,
                                   confirmation: confirmation)

      assert_operator result.deleted_rows, :>, 0
      assert_equal 1, result.deleted_blobs
      assert_not Tenant.exists?(tenant.id)
      assert_empty Tenants::DataInventory.new(tenant.id).counts
      assert_not ActiveStorage::Blob.exists?(blob_id)
      assert Tenant.exists?(tenants(:primary).id)
      assert AuditEntry.verify_chain(cache: false, checkpoint: false)[:ok]
      assert_empty AuditEntry.where(tenant_id: tenant.id)
      assert AuditEntry.where(action: "tenant.purge_authorized").exists?
    end
  end

  test "refuses an old export after tenant data changes" do
    tenant = tenants(:acme)
    tenant.suspended!

    Dir.mktmpdir("docket-purge-stale") do |dir|
      export = Tenants::Export.call(tenant: tenant, path: File.join(dir, "archive"))
      ActsAsTenant.with_tenant(tenant) do
        Contact.create!(name: "Written after export", email: "after-export@example.test")
      end

      error = assert_raises(Tenants::Purge::Error) do
        Tenants::Purge.call(
          tenant: tenant, receipt: export.receipt,
          confirmation: "PURGE #{tenant.slug} #{export.receipt.export_id}"
        )
      end
      assert_includes error.message, "changed after export"
    end
  end
end
