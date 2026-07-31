module Imports
  # Validates and attaches historical blobs while keying the blob to the
  # provider's attachment id. A resumed batch reuses the linked blob rather
  # than downloading or storing it twice.
  class Attachments
    FIELDS = %w[
      id name filename file_name content_type mimeType size byte_size checksum
      attachment_url content_url url content data created_at updated_at
    ].freeze

    def initialize(session:, downloader: nil, export_root: nil)
      @session = session
      @downloader = downloader
      @export_root = Pathname(export_root).realpath if export_root
    end

    def import(record:, rows:, parent_external_id:, source_type: "attachment")
      Array(rows).each_with_index do |row, index|
        io = nil
        unless row.is_a?(Hash)
          @session.result.error!("attachment: expected an object, got #{row.class}")
          next
        end
        FieldContract.new(@session.result, source_type, FIELDS).inspect!(row)
        external_id = row["id"].presence || fallback_id(parent_external_id, row, index)
        existing = @session.identity_target(source_type, external_id.to_s)
        if existing.is_a?(ActiveStorage::Blob) && record.files.blobs.exists?(existing.id)
          @session.result.skip!("attachments")
          next
        end
        if record.files.count >= AttachableValidation::MAX_FILES
          @session.result.unmapped!("attachment_limit", external_id)
          @session.result.skip!("attachments")
          next
        end

        content_type = row["content_type"].presence || row["mimeType"].presence
        unless AttachableValidation::ALLOWED_CONTENT_TYPES.include?(content_type)
          @session.result.unmapped!("attachment_content_type", content_type.presence || "missing")
          @session.result.skip!("attachments")
          next
        end
        declared_size = row["size"].presence || row["byte_size"].presence
        if declared_size.to_i > AttachableValidation::MAX_FILE_SIZE
          @session.result.unmapped!("attachment_too_large", external_id)
          @session.result.skip!("attachments")
          next
        end
        if @session.dry_run?
          @session.result.create!("attachments")
          next
        end

        material = materialize(row, content_type)
        if material.nil?
          @session.result.unmapped!("attachment_body", external_id)
          @session.result.skip!("attachments")
          next
        end
        io = material.fetch(:io)
        if io_size(io) > AttachableValidation::MAX_FILE_SIZE
          @session.result.unmapped!("attachment_too_large", external_id)
          @session.result.skip!("attachments")
          next
        end

        blob = existing || ActiveStorage::Blob.create_and_upload!(
          io: io,
          filename: material[:filename].presence || filename(row, external_id),
          content_type: material[:content_type].presence || content_type,
          identify: false
        )
        record.files.attach(blob) unless record.files.blobs.exists?(blob.id)
        unless record.valid?
          @session.result.error!("attachment #{external_id}: #{record.errors.full_messages.to_sentence}")
          blob.purge if existing.nil?
          next
        end
        @session.link_identity(
          source_type: source_type, external_id: external_id, target: blob,
          source_updated_at: row["updated_at"] || row["created_at"],
          imported_attributes: {
            filename: blob.filename.to_s, content_type: blob.content_type,
            byte_size: blob.byte_size, checksum: blob.checksum
          }
        )
        @session.result.create!("attachments") if existing.nil?
      ensure
        io.close if defined?(io) && io.respond_to?(:close) && !io.closed?
      end
    end

    private

    def materialize(row, content_type)
      return @downloader.download_attachment(row) if @downloader&.respond_to?(:download_attachment)
      if row["data"].present?
        bytes = Base64.strict_decode64(row["data"].to_s)
        return { io: StringIO.new(bytes), filename: filename(row, row["id"]),
                 content_type: content_type }
      end
      if row["content"].present? && local_file?(row["content"])
        path = safe_local_path(row["content"])
        return { io: File.open(path, "rb"), filename: filename(row, path.basename),
                 content_type: content_type }
      end

      nil
    rescue ArgumentError, Errno::ENOENT, SecurityError, HttpSource::Error => e
      @session.result.error!("attachment #{row['id']}: #{e.message}")
      nil
    end

    def local_file?(value)
      @export_root && !value.to_s.match?(%r{\Ahttps?://}i)
    end

    def safe_local_path(value)
      candidate = @export_root.join(value.to_s).realpath
      root = @export_root.to_s.end_with?(File::SEPARATOR) ? @export_root.to_s : "#{@export_root}#{File::SEPARATOR}"
      raise SecurityError, "attachment path escapes the export directory" unless candidate.to_s.start_with?(root)

      candidate
    end

    def filename(row, fallback)
      row["name"].presence || row["filename"].presence || row["file_name"].presence ||
        "attachment-#{fallback}"
    end

    def io_size(io)
      return io.size if io.respond_to?(:size)

      current = io.pos
      io.seek(0, IO::SEEK_END)
      size = io.pos
      io.seek(current, IO::SEEK_SET)
      size
    end

    def fallback_id(parent_external_id, row, index)
      Digest::SHA256.hexdigest(
        [ parent_external_id, filename(row, index), row["size"], index ].join("\0")
      )
    end
  end
end
