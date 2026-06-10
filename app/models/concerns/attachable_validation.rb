# Upload posture (handoff §8): tight type allowlist, per-file size cap,
# bounded count. Applied to every surface that accepts files.
module AttachableValidation
  extend ActiveSupport::Concern

  ALLOWED_CONTENT_TYPES = %w[
    image/png image/jpeg image/gif image/webp
    application/pdf text/plain text/csv
  ].freeze
  MAX_FILE_SIZE = 10.megabytes
  MAX_FILES = 5

  included do
    validate :validate_attached_files
  end

  private

  def validate_attached_files
    return unless files.attached?

    if files.size > MAX_FILES
      errors.add(:files, :too_many, count: MAX_FILES)
    end

    files.each do |file|
      unless ALLOWED_CONTENT_TYPES.include?(file.content_type)
        errors.add(:files, :unsupported_type, filename: file.filename.to_s)
      end
      if file.byte_size > MAX_FILE_SIZE
        errors.add(:files, :too_large, filename: file.filename.to_s, max: MAX_FILE_SIZE / 1.megabyte)
      end
    end
  end
end
