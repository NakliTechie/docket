module Imports
  # Durable import execution boundary. Business rows commit in bounded batches;
  # the checkpoint commits only after its batch, so a crash safely replays at
  # most one idempotent batch. Dry runs execute the same validations and then
  # roll each batch back while retaining an honest result.
  class Session
    class ResumeError < StandardError; end

    attr_reader :result, :run, :source, :source_instance, :batch_size

    def dry_run? = @dry_run

    def initialize(source:, source_instance: "default", dry_run: true, batch_size: 200,
                   resume_token: nil, options: {}, result: nil)
      @source = source.to_s
      @source_instance = source_instance.to_s.presence || "default"
      @dry_run = dry_run
      @batch_size = Integer(batch_size)
      raise ArgumentError, "batch_size must be between 1 and 1000" unless (1..1000).cover?(@batch_size)

      @result = result || Result.new
      @dry_identities = {}
      @run = resume_token.present? ? resume_run!(resume_token) : create_run!(options)
      @result.run_id = @run.id
      @result.resume_token = @run.resume_token
      @result.watermark = @run.previous_watermark
    end

    def process(rows, stream:, cursor: nil)
      checkpoint = run.checkpoint.to_h.fetch(stream.to_s, {})
      cursor_reader = cursor if cursor.respond_to?(:call)
      prior_cursor = checkpoint["cursor"] if cursor_reader
      offset = cursor_reader ? 0 : Integer(checkpoint.fetch("offset", 0))
      pending = []

      rows.each_with_index do |row, index|
        next if index < offset

        row_cursor = cursor_reader&.call(row)
        if cursor_reader
          raise ResumeError, "#{stream} row is missing its stable import cursor" if row_cursor.blank?
          next if prior_cursor && compare_cursors(row_cursor, prior_cursor) <= 0
        end

        pending << [ row, index + 1, row_cursor ]
        next unless pending.length >= batch_size

        flush(pending, stream) { |entry| yield entry }
        pending.clear
      end
      flush(pending, stream) { |entry| yield entry }
      self
    rescue StandardError => e
      run.fail!(e)
      raise
    end

    def finish!
      run.finish!(result)
      self
    end

    def sync(source_type:, external_id:, kind:, attributes:, source_updated_at: nil,
             metadata: {}, existing: nil, overwrite_local: false)
      external_id = external_id.to_s
      raise ArgumentError, "external_id is required" if external_id.blank?

      identity = identity_for(source_type, external_id)
      linked_target = live_target(identity)
      target = linked_target || existing
      new_target = target.nil?
      target ||= yield
      # Importers construct sparse hashes: absence means "leave local value
      # alone", while an explicitly present nil may be a real source deletion.
      normalized = normalize_attributes(attributes)
      digest = Digest::SHA256.hexdigest(JSON.generate(ImportIdentity.canonicalize(normalized)))

      if identity&.source_digest == digest && target.persisted?
        touch_identity(identity, target, source_updated_at, digest, normalized, metadata)
        result.skip!(kind)
        result.observe_watermark(source_updated_at)
        return target
      end

      # A tombstoned/missing old target is a replacement, not a locally edited
      # continuation. Its old snapshot must not conflict every required field
      # off the new blank record.
      conflict_identity = linked_target ? identity : nil
      assignable = conflict_filtered_attributes(conflict_identity, target, normalized,
                                                source_type, external_id, overwrite_local)
      target.assign_attributes(assignable)
      target.save!
      identity ||= build_identity(source_type, external_id)
      touch_identity(identity, target, source_updated_at, digest, normalized, metadata)
      new_target ? result.create!(kind) : result.update!(kind)
      result.observe_watermark(source_updated_at)
      target
    end

    def identity_target(source_type, external_id)
      live_target(identity_for(source_type, external_id.to_s))
    end

    def link_identity(source_type:, external_id:, target:, source_updated_at: nil,
                      metadata: {}, imported_attributes: {})
      identity = identity_for(source_type, external_id.to_s) ||
                 build_identity(source_type, external_id.to_s)
      normalized = normalize_attributes(imported_attributes)
      digest = Digest::SHA256.hexdigest(JSON.generate(ImportIdentity.canonicalize(normalized)))
      touch_identity(identity, target, source_updated_at, digest, normalized, metadata)
      target
    end

    def tombstone(source_type:, external_id:, kind:, source_updated_at: nil, metadata: {},
                  existing: nil)
      external_id = external_id.to_s
      raise ArgumentError, "external_id is required" if external_id.blank?

      identity = identity_for(source_type, external_id) || build_identity(source_type, external_id)
      target = stored_target(identity) || existing
      was_live = target.present? && (!target.respond_to?(:deleted?) || !target.deleted?)
      target.destroy! if was_live
      marker = { "_source_deleted" => true }
      digest = Digest::SHA256.hexdigest(JSON.generate(marker))
      touch_identity(identity, target, source_updated_at, digest, marker,
                     metadata.merge("source_deleted" => true))
      was_live ? result.delete!(kind) : result.skip!(kind)
      result.observe_watermark(source_updated_at)
      target
    end

    def checkpoint!(stream, offset:, cursor: nil)
      all = run.checkpoint.to_h
      all[stream.to_s] = { "offset" => offset, "cursor" => cursor }.compact
      run.update!(checkpoint: all, stats: result.counts,
                  unmapped: result.serialized_unmapped, error_messages: result.errors,
                  conflicts: result.conflicts, watermark: result.watermark)
    end

    private

    def create_run!(options)
      previous = ImportRun.latest_watermark(source: source, source_instance: source_instance)
      ImportRun.create!(source: source, source_instance: source_instance,
                        dry_run: @dry_run, previous_watermark: previous,
                        options: redact_options(options))
    end

    def resume_run!(token)
      candidate = ImportRun.find_by!(resume_token: token)
      unless candidate.source == source && candidate.source_instance == source_instance
        raise ResumeError, "resume token belongs to a different source"
      end
      if candidate.dry_run != @dry_run
        raise ResumeError, "a dry-run checkpoint cannot be resumed as an apply run"
      end
      unless %w[running failed].include?(candidate.status)
        raise ResumeError, "#{candidate.status.tr('_', ' ')} imports cannot be resumed"
      end

      candidate.update!(status: "running", completed_at: nil)
      candidate
    end

    def flush(entries, stream)
      return if entries.empty?

      Mode.run do
        # `requires_new` matters under Rails' transactional test wrapper and
        # when a caller already owns a transaction: dry-run rollback must stop
        # at this batch, not be swallowed while joined to the outer transaction.
        ActiveRecord::Base.transaction(requires_new: true) do
          entries.each do |entry, _next_offset, _entry_cursor|
            ActiveRecord::Base.transaction(requires_new: true) do
              yield entry
              result.process!
            rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
              result.error!(e.message)
              raise ActiveRecord::Rollback
            end
          end
          raise ActiveRecord::Rollback if @dry_run
        end
      end
      last_entry = entries.last
      checkpoint!(stream, offset: last_entry[1], cursor: last_entry[2])
    end

    def identity_for(source_type, external_id)
      key = [ source_type.to_s, external_id ]
      return @dry_identities[key] if @dry_identities.key?(key)

      ImportIdentity.for_source(source, source_instance)
                    .find_by(source_type: source_type.to_s, external_id: external_id)
    end

    def build_identity(source_type, external_id)
      identity = ImportIdentity.new(source: source, source_instance: source_instance,
                                    source_type: source_type.to_s, external_id: external_id)
      @dry_identities[[ source_type.to_s, external_id ]] = identity if @dry_run
      identity
    end

    def touch_identity(identity, target, source_updated_at, digest, attributes, metadata)
      identity.assign_attributes(target: target,
                                 source_updated_at: parse_time(source_updated_at),
                                 source_digest: digest,
                                 imported_attributes: attributes,
                                 metadata: identity.metadata.to_h.merge(metadata.stringify_keys))
      # Keeping a rolled-back identity in `run.import_identities` lets
      # ActiveRecord autosave its target when the durable run checkpoint is
      # updated — silently turning a dry run into an apply. Dry identities live
      # only in this Session's in-memory map.
      return identity if @dry_run

      identity.last_seen_run = run
      identity.save!
    end

    def live_target(identity)
      return if identity.nil? || identity.target_type.blank? || identity.target_id.blank?

      klass = identity.target_type.constantize
      scope = klass.respond_to?(:with_deleted) ? klass.with_deleted : klass.all
      target = scope.find_by(id: identity.target_id)
      return if target&.respond_to?(:deleted?) && target.deleted?

      target
    rescue NameError
      nil
    end

    def stored_target(identity)
      return if identity.nil? || identity.target_type.blank? || identity.target_id.blank?

      klass = identity.target_type.constantize
      scope = klass.respond_to?(:with_deleted) ? klass.with_deleted : klass.all
      scope.find_by(id: identity.target_id)
    rescue NameError
      nil
    end

    def compare_cursors(left, right)
      left = left.stringify_keys
      right = right.stringify_keys
      time_comparison = parse_time(left.fetch("updated_at")) <=> parse_time(right.fetch("updated_at"))
      return time_comparison unless time_comparison.zero?

      compare_stable_ids(left.fetch("id"), right.fetch("id"))
    rescue KeyError, ArgumentError
      raise ResumeError, "stable import cursors require updated_at and id"
    end

    def compare_stable_ids(left, right)
      left = left.to_s
      right = right.to_s
      return left.to_i <=> right.to_i if left.match?(/\A\d+\z/) && right.match?(/\A\d+\z/)

      left <=> right
    end

    def conflict_filtered_attributes(identity, target, incoming, source_type, external_id,
                                     overwrite_local)
      return incoming if identity.nil? || overwrite_local

      previous = identity.imported_attributes.to_h
      incoming.each_with_object({}) do |(field, value), accepted|
        old_imported = previous[field]
        current = normalize_value(target.public_send(field))
        if previous.key?(field) && current != old_imported && value != old_imported
          record_conflict(identity, target, source_type, external_id, field,
                          old_imported, current, value)
        else
          accepted[field] = value
        end
      end
    end

    def record_conflict(identity, target, source_type, external_id, field, previous, current, incoming)
      details = {
        source_type: source_type.to_s, external_id: external_id, field: field,
        previous_imported_value: previous, current_value: current, incoming_value: incoming
      }
      result.conflict!(details)
      ImportConflict.create!(import_run: run, import_identity: identity,
                             source_type: source_type.to_s, external_id: external_id,
                             target: target, field: field,
                             previous_imported_value: previous, current_value: current,
                             incoming_value: incoming)
    end

    def normalize_attributes(attributes)
      attributes.stringify_keys.transform_values { |value| normalize_value(value) }
    end

    def normalize_value(value)
      case value
      when ActiveRecord::Base then value.id
      when Time, ActiveSupport::TimeWithZone, DateTime then value.utc.iso8601(6)
      when Date then value.iso8601
      when Symbol then value.to_s
      when Hash then value.stringify_keys.transform_values { |nested| normalize_value(nested) }
      when Array then value.map { |nested| normalize_value(nested) }
      else value
      end
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def redact_options(options)
      options.stringify_keys.transform_values.with_index do |value, _index|
        value.is_a?(String) && value.length > 200 ? "[REDACTED]" : value
      end
    end
  end
end
