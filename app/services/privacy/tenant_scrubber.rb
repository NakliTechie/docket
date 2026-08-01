module Privacy
  class TenantScrubber
    TEXT_TYPES = %i[string text json jsonb].freeze

    def self.call(...) = new(...).call

    def initialize(tenant:, identifiers:, token:)
      @tenant = tenant
      @identifiers = identifiers.compact_blank.map(&:to_s).uniq.sort_by { |value| -value.length }
      @token = token
      @connection = ApplicationRecord.connection
    end

    def call
      changed = 0
      inventory = Tenants::DataInventory.new(@tenant)
      inventory.tables.each do |table|
        columns = scrub_columns(table)
        next if columns.empty?

        inventory.rows(table).each do |row|
          updates = columns.each_with_object({}) do |column, values|
            value = row[column.name]
            scrubbed = scrub(value, table: table, row_id: row.fetch(@connection.primary_key(table)),
                                    column: column)
            values[column.name] = scrubbed if scrubbed != value
          end
          next if updates.empty?

          update_row(table, row.fetch(@connection.primary_key(table)), updates)
          changed += updates.size
        end
      end
      changed
    end

    private

    def scrub_columns(table)
      @connection.columns(table).select { |column| TEXT_TYPES.include?(column.type) }
    end

    def scrub(value, table:, row_id:, column:)
      return value if value.nil?

      if %i[json jsonb].include?(column.type)
        parsed = value.is_a?(String) ? JSON.parse(value) : value
        scrub_json(parsed, table: table, row_id: row_id, column: column.name)
      else
        scrub_string(value.to_s, table: table, row_id: row_id, column: column.name)
      end
    rescue JSON::ParserError
      scrub_string(value.to_s, table: table, row_id: row_id, column: column.name)
    end

    def scrub_json(value, **context)
      case value
      when Hash then value.transform_values { |nested| scrub_json(nested, **context) }
      when Array then value.map { |nested| scrub_json(nested, **context) }
      when String then scrub_string(value, **context)
      else value
      end
    end

    def scrub_string(value, table:, row_id:, column:)
      replacement = "[ERASED:#{@token}:#{Digest::SHA256.hexdigest("#{table}:#{row_id}:#{column}").first(8)}]"
      @identifiers.reduce(value) { |text, identifier| text.gsub(identifier, replacement) }
    end

    def update_row(table, id, updates)
      assignments = updates.map do |column, value|
        serialized = if value.is_a?(Hash) || value.is_a?(Array)
          JSON.generate(value)
        else
          value
        end
        "#{@connection.quote_column_name(column)} = #{@connection.quote(serialized)}"
      end
      @connection.update(<<~SQL.squish)
        UPDATE #{@connection.quote_table_name(table)} SET #{assignments.join(', ')}
        WHERE #{@connection.quote_column_name(@connection.primary_key(table))} = #{@connection.quote(id)}
      SQL
    end
  end
end
