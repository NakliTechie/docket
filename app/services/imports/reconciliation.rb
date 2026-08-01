module Imports
  # Compares a source-side inventory captured at cutover with durable import
  # identities. This is intentionally read-only: discrepancies must be visible
  # before an operator chooses to re-run, keep local, or accept source.
  class Reconciliation
    def self.call(...) = new(...).call

    def initialize(source:, inventory:, source_instance: "default", full: true)
      @source = source.to_s
      @source_instance = source_instance.to_s
      @inventory = inventory
      @full = full
    end

    def call
      source_rows = normalized_inventory
      identities = ImportIdentity.for_source(@source, @source_instance).to_a
      by_key = identities.index_by { |identity| key(identity.source_type, identity.external_id) }
      source_by_key = source_rows.index_by { |row| key(row.fetch("source_type"), row.fetch("external_id")) }
      duplicate_source_ids = duplicate_keys(source_rows)
      missing_targets = identities.filter_map do |identity|
        identity_descriptor(identity) unless live_target?(identity)
      end
      missing_in_docket = source_rows.filter_map do |row|
        row unless by_key.key?(key(row.fetch("source_type"), row.fetch("external_id")))
      end
      stale = source_rows.filter_map do |row|
        identity = by_key[key(row.fetch("source_type"), row.fetch("external_id"))]
        next unless identity && row["updated_at"].present?
        source_time = parse_time(row["updated_at"])
        next unless source_time && (identity.source_updated_at.nil? || source_time > identity.source_updated_at)

        row.merge("docket_source_updated_at" => identity.source_updated_at&.iso8601)
      end
      missing_in_source = if @full
        identities.filter_map do |identity|
          identity_descriptor(identity) unless source_by_key.key?(key(identity.source_type, identity.external_id))
        end
      else
        []
      end
      conflicts = ImportConflict.where(
        tenant_id: ActsAsTenant.current_tenant&.id,
        status: "unresolved",
        import_run_id: ImportRun.where(source: @source, source_instance: @source_instance)
      ).order(:id).map do |conflict|
        {
          source_type: conflict.source_type, external_id: conflict.external_id,
          field: conflict.field, current_value: conflict.current_value,
          incoming_value: conflict.incoming_value
        }
      end
      latest = ImportRun.clean_applied.where(source: @source, source_instance: @source_instance)
                        .order(completed_at: :desc).first
      {
        ok: duplicate_source_ids.empty? && missing_targets.empty? &&
          missing_in_docket.empty? && missing_in_source.empty? && stale.empty? && conflicts.empty?,
        source: @source, source_instance: @source_instance, full_inventory: @full,
        counts: {
          source: source_rows.size, identities: identities.size,
          live_targets: identities.count { |identity| live_target?(identity) }
        },
        duplicate_source_ids: duplicate_source_ids,
        missing_targets: missing_targets,
        missing_in_docket: missing_in_docket,
        missing_in_source: missing_in_source,
        stale_source_rows: stale,
        unresolved_conflicts: conflicts,
        last_completed_run_id: latest&.id,
        imported_watermark: latest&.watermark&.iso8601
      }
    end

    private

    def normalized_inventory
      rows = if @inventory.is_a?(Hash)
        @inventory.flat_map do |source_type, entries|
          Array(entries).map do |entry|
            entry.is_a?(Hash) ? entry.stringify_keys.merge("source_type" => source_type.to_s) :
              { "source_type" => source_type.to_s, "external_id" => entry.to_s }
          end
        end
      else
        Array(@inventory).map(&:stringify_keys)
      end
      rows.filter_map do |row|
        external_id = row["external_id"].presence || row["id"].presence
        next if external_id.blank? || row["source_type"].blank?

        row.merge("external_id" => external_id.to_s)
      end
    end

    def duplicate_keys(rows)
      rows.group_by { |row| key(row.fetch("source_type"), row.fetch("external_id")) }
          .select { |_, grouped| grouped.size > 1 }.keys
          .map { |source_type, external_id| { source_type: source_type, external_id: external_id } }
    end

    def live_target?(identity)
      return false if identity.target_type.blank? || identity.target_id.blank?

      klass = identity.target_type.constantize
      scope = klass.respond_to?(:with_deleted) ? klass.with_deleted : klass.all
      target = scope.find_by(id: identity.target_id)
      target.present? && (!target.respond_to?(:deleted?) || !target.deleted?)
    rescue NameError
      false
    end

    def identity_descriptor(identity)
      {
        source_type: identity.source_type, external_id: identity.external_id,
        target_type: identity.target_type, target_id: identity.target_id
      }
    end

    def key(source_type, external_id)
      [ source_type.to_s, external_id.to_s ]
    end

    def parse_time(value)
      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
