class RepairPostgresqlJsonColumns < ActiveRecord::Migration[8.1]
  def up
    return unless connection.adapter_name.match?(/postgres/i)

    connection.tables.each do |table|
      connection.columns(table).select { |column| column.sql_type == "json" }.each do |column|
        quoted_table = connection.quote_table_name(table)
        quoted_column = connection.quote_column_name(column.name)
        execute <<~SQL.squish
          ALTER TABLE #{quoted_table}
          ALTER COLUMN #{quoted_column} TYPE jsonb
          USING #{quoted_column}::jsonb
        SQL
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "this repair normalizes accidentally schema-loaded PostgreSQL json columns"
  end
end
