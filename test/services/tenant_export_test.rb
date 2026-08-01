require "test_helper"
require "tmpdir"

class TenantExportTest < ActiveSupport::TestCase
  test "exports only the tenant graph, ciphertext, attachments, and checksummed manifest" do
    tenant = tenants(:acme)
    tenant.suspended!
    record = nil
    attachment = nil
    ActsAsTenant.with_tenant(tenant) do
      contact = Contact.create!(name: "Acme Export", email: "export@acme.test")
      record = Case.create!(subject: "Acme archive", contact: contact)
      record.files.attach(io: StringIO.new("tenant attachment"), filename: "proof.txt",
                          content_type: "text/plain")
      attachment = record.files.first
      credential = SharedCredential.new(name: "export_key", label: "Export key")
      credential.secrets_hash = { "api_key" => "must-not-be-plaintext" }
      credential.save!
    end

    Dir.mktmpdir("docket-export-test") do |dir|
      result = Tenants::Export.call(tenant: tenant, path: File.join(dir, "archive"))
      manifest_path = result.path.join("manifest.json")
      manifest = JSON.parse(manifest_path.read)

      assert_equal "docket-tenant-export-v1", manifest.fetch("format")
      assert_equal tenant.slug, manifest.dig("tenant", "slug")
      assert_equal result.receipt.inventory_sha256, manifest.fetch("inventory_sha256")
      assert result.receipt.current_inventory?
      assert result.receipt.archive_intact?
      assert_equal Digest::SHA256.file(manifest_path).hexdigest,
                   result.receipt.manifest_sha256

      contacts = result.path.join("data/contacts.jsonl").read
      assert_includes contacts, "export@acme.test"
      refute_includes contacts, contacts(:asha).email
      credentials = result.path.join("data/shared_credentials.jsonl").read
      refute_includes credentials, "must-not-be-plaintext"

      exported_file = result.path.join("attachments/#{attachment.id}/proof.txt")
      assert_equal "tenant attachment", exported_file.read
      file_manifest = manifest.fetch("files").find { |file| file["path"] == "attachments/#{attachment.id}/proof.txt" }
      assert_equal Digest::SHA256.file(exported_file).hexdigest, file_manifest.fetch("sha256")
    end
  end

  test "refuses to export a tenant that has not been quiesced" do
    tenant = tenants(:acme)

    assert_raises(ArgumentError) { Tenants::Export.call(tenant: tenant) }
  end
end
