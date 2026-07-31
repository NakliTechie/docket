class TenantExportReceipt < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  validates :export_id, :manifest_sha256, :inventory_sha256, :export_path, :completed_at, presence: true
  validates :export_id, uniqueness: true
  validates :manifest_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :inventory_sha256, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :attachment_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def archive_intact?
    root = Pathname(export_path).expand_path
    manifest_path = root.join("manifest.json")
    return false unless manifest_path.file?
    return false unless secure_compare(Digest::SHA256.file(manifest_path).hexdigest, manifest_sha256)

    manifest = JSON.parse(manifest_path.read)
    return false unless manifest["format"] == "docket-tenant-export-v1"
    return false unless manifest["export_id"] == export_id
    return false unless manifest.dig("tenant", "id").to_i == tenant_id
    return false unless manifest["row_counts"] == row_counts
    return false unless manifest["attachment_count"].to_i == attachment_count
    return false unless secure_compare(manifest["inventory_sha256"], inventory_sha256)

    Array(manifest["files"]).all? { |entry| archived_file_intact?(root, entry) }
  rescue JSON::ParserError, SystemCallError, TypeError
    false
  end

  def current_inventory?
    secure_compare(Tenants::DataInventory.new(tenant_id).state_sha256, inventory_sha256)
  end

  private

  def archived_file_intact?(root, entry)
    relative = Pathname(entry.fetch("path"))
    return false if relative.absolute? || relative.each_filename.any? { |part| part == ".." }

    target = root.join(relative).expand_path
    return false unless target.to_s.start_with?("#{root}/") && target.file?
    return false unless target.size == Integer(entry.fetch("bytes"))

    secure_compare(Digest::SHA256.file(target).hexdigest, entry.fetch("sha256"))
  rescue KeyError, ArgumentError, SystemCallError
    false
  end

  def secure_compare(left, right)
    return false unless left.to_s.bytesize == right.to_s.bytesize

    ActiveSupport::SecurityUtils.secure_compare(left.to_s, right.to_s)
  end
end
