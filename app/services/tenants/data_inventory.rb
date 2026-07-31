module Tenants
  class DataInventory
    GLOBAL_TABLES = %w[
      ar_internal_metadata schema_migrations tenants audit_entries
      solid_cache_entries solid_cable_messages
    ].freeze

    attr_reader :tenant_id, :connection

    def initialize(tenant_or_id)
      @tenant_id = Integer(tenant_or_id.respond_to?(:id) ? tenant_or_id.id : tenant_or_id)
      @connection = ApplicationRecord.connection
    end

    def owned_ids
      @owned_ids ||= build_owned_ids
    end

    def counts
      owned_ids.transform_values(&:size).select { |_, count| count.positive? }
    end

    def rows(table)
      ids = owned_ids.fetch(table.to_s, [])
      return [] if ids.empty?

      relation = arel_table(table)
      primary_key = relation[connection.primary_key(table)]
      connection.select_all(
        relation.project(Arel.star).where(primary_key.in(ids)).order(primary_key.asc)
      ).to_a
    end

    def tables
      owned_ids.keys.sort
    end

    def deletion_order
      nodes = tables.to_set
      edges = nodes.index_with { Set.new }
      nodes.each do |child|
        connection.foreign_keys(child).each do |foreign_key|
          parent = foreign_key.to_table
          edges[child] << parent if nodes.include?(parent) && parent != child
        end
      end

      incoming = nodes.index_with { 0 }
      edges.each_value { |parents| parents.each { |parent| incoming[parent] += 1 } }
      ready = incoming.select { |_, degree| degree.zero? }.keys.sort
      ordered = []
      until ready.empty?
        child = ready.shift
        ordered << child
        edges.fetch(child).each do |parent|
          incoming[parent] -= 1
          ready << parent if incoming[parent].zero?
        end
        ready.sort!
      end
      ordered + (nodes.to_a - ordered).sort
    end

    def attachment_rows
      rows("active_storage_attachments")
    end

    # A deterministic fingerprint of the current tenant-owned database graph.
    # Export receipts are excluded because creating the receipt is itself the
    # final step of exporting and must not make that export immediately stale.
    def state_sha256(exclude_tables: %w[tenant_export_receipts])
      digest = Digest::SHA256.new
      tables.sort.each do |table|
        next if exclude_tables.include?(table)

        digest << "table:#{table}\n"
        rows(table).each do |row|
          digest << JSON.generate(row.sort.to_h) << "\n"
        end
      end
      attachment_rows.sort_by { |row| row.fetch("id") }.each do |row|
        blob = ActiveStorage::Blob.find_by(id: row.fetch("blob_id"))
        digest << JSON.generate(blob&.attributes&.sort&.to_h || {}) << "\n"
      end
      digest.hexdigest
    end

    def residue?
      counts.any?
    end

    private

    def build_owned_ids
      inventory = direct_tables.index_with { |table| ids_for_tenant(table) }
      expand_foreign_key_children!(inventory)
      add_polymorphic_attachments!(inventory)
      inventory.transform_values { |ids| ids.compact.uniq.sort }
    end

    def direct_tables
      connection.tables.select do |table|
        !GLOBAL_TABLES.include?(table) &&
          connection.primary_key(table).present? &&
          connection.columns(table).any? { |column| column.name == "tenant_id" }
      end.sort
    end

    def ids_for_tenant(table)
      relation = arel_table(table)
      connection.select_values(
        relation.project(relation[connection.primary_key(table)])
                .where(relation[:tenant_id].eq(tenant_id))
      )
    end

    def expand_foreign_key_children!(inventory)
      loop do
        changed = false
        connection.tables.sort.each do |child|
          next if GLOBAL_TABLES.include?(child) || connection.primary_key(child).blank?
          next if inventory.key?(child) && direct_table?(child)

          candidate_ids = connection.foreign_keys(child).flat_map do |foreign_key|
            parent_ids = inventory[foreign_key.to_table]
            next [] if parent_ids.blank?

            child_ids_for_parent(child, foreign_key, parent_ids)
          end
          next if candidate_ids.empty?

          before = inventory.fetch(child, []).size
          inventory[child] = (inventory.fetch(child, []) + candidate_ids).uniq
          changed ||= inventory[child].size > before
        end
        break unless changed
      end
    end

    def direct_table?(table)
      connection.columns(table).any? { |column| column.name == "tenant_id" }
    end

    def child_ids_for_parent(child, foreign_key, parent_ids)
      relation = arel_table(child)
      connection.select_values(
        relation.project(relation[connection.primary_key(child)])
                .where(relation[foreign_key.options.fetch(:column)].in(parent_ids))
      )
    end

    def add_polymorphic_attachments!(inventory)
      return unless connection.table_exists?("active_storage_attachments")

      rows = connection.select_rows(<<~SQL.squish)
        SELECT id, record_type, record_id FROM active_storage_attachments
      SQL
      record_ids_by_table = inventory.transform_values { |ids| ids.map(&:to_s).to_set }
      attachment_ids = rows.filter_map do |id, type, record_id|
        table = type.to_s.safe_constantize&.table_name
        id if table && record_ids_by_table.fetch(table, Set.new).include?(record_id.to_s)
      end
      inventory["active_storage_attachments"] = attachment_ids if attachment_ids.any?
    end

    def arel_table(table)
      Arel::Table.new(table)
    end
  end
end
