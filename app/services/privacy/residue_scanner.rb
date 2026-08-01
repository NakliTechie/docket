module Privacy
  class ResidueScanner
    Result = Data.define(:matches) do
      def clean? = matches.empty?
    end

    def self.call(...) = new(...).call

    def initialize(tenant:, identifiers:)
      @tenant = tenant
      @identifiers = identifiers.compact_blank.map(&:to_s).uniq
    end

    def call
      inventory = Tenants::DataInventory.new(@tenant)
      matches = inventory.tables.flat_map do |table|
        inventory.rows(table).filter_map { |row| match_for(table, row) }
      end
      audit_matches = AuditEntry.where(tenant_id: @tenant.id).filter_map do |entry|
        match_for("audit_entries", entry.attributes)
      end
      Result.new(matches: matches + audit_matches)
    end

    private

    def match_for(table, row)
      primary_key = ApplicationRecord.connection.primary_key(table) || "id"
      columns = row.filter_map do |column, value|
        serialized = value.is_a?(String) ? value : JSON.generate(value)
        column if @identifiers.any? { |identifier| serialized.include?(identifier) }
      end
      { table: table, id: row[primary_key], columns: columns } if columns.any?
    end
  end
end
