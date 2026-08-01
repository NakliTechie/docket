class ConvertJsonColumnsToJsonb < ActiveRecord::Migration[8.1]
  COLUMNS = {
    audit_entries: %i[changeset metadata],
    cases: %i[labels],
    connector_invocations: %i[args result],
    connectors: %i[auto_approve_actions config enabled_actions field_mapping],
    deals: %i[labels],
    decisions: %i[action_params],
    leads: %i[labels],
    messages: %i[metadata],
    oauth_access_tokens: %i[scopes],
    security_events: %i[metadata],
    sequence_deliveries: %i[payload],
    service_accounts: %i[scopes],
    settings: %i[value],
    sprints: %i[rolled_out_item_ids],
    tenants: %i[entitlements],
    webhook_deliveries: %i[payload],
    webhook_endpoints: %i[events],
    work_items: %i[labels]
  }.freeze

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
    COLUMNS.each do |table, columns|
      columns.each do |column|
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
end
