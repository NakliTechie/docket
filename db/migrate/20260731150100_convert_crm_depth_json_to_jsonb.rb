class ConvertCrmDepthJsonToJsonb < ActiveRecord::Migration[8.1]
  COLUMNS = { lead_capture_forms: :field_mapping, leads: :provenance }.freeze

  def up
    convert(:jsonb) if postgresql?
  end

  def down
    convert(:json) if postgresql?
  end

  private

  def postgresql?
    connection.adapter_name.match?(/postgres/i)
  end

  def convert(type)
    COLUMNS.each do |table, column|
      quoted_table = connection.quote_table_name(table)
      quoted_column = connection.quote_column_name(column)
      execute <<~SQL.squish
        ALTER TABLE #{quoted_table}
        ALTER COLUMN #{quoted_column} TYPE #{type}
        USING #{quoted_column}::#{type}
      SQL
    end
  end
end
