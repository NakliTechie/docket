require "test_helper"

class JsonColumnTypesTest < ActiveSupport::TestCase
  EXPECTED = {
    audit_entries: %i[changeset metadata], cases: %i[labels custom_fields],
    contacts: %i[labels custom_fields], deals: %i[labels custom_fields], leads: %i[labels provenance custom_fields],
    connector_invocations: %i[args result],
    connectors: %i[auto_approve_actions config enabled_actions field_mapping],
    decisions: %i[action_params],
    messages: %i[metadata], oauth_access_tokens: %i[scopes],
    security_events: %i[metadata], sequence_deliveries: %i[payload],
    service_accounts: %i[scopes], settings: %i[value],
    sprints: %i[rolled_out_item_ids], tenants: %i[entitlements],
    webhook_deliveries: %i[payload], webhook_endpoints: %i[events],
    custom_field_definitions: %i[options], work_items: %i[labels custom_fields]
  }.freeze

  test "structured columns use the adapter's production-safe JSON type" do
    expected_type = ActiveRecord::Base.connection.adapter_name.match?(/postgres/i) ? "jsonb" : "json"

    EXPECTED.each do |table, columns|
      definitions = ActiveRecord::Base.connection.columns(table).index_by { |column| column.name.to_sym }
      columns.each do |name|
        assert_equal expected_type, definitions.fetch(name).sql_type,
                     "#{table}.#{name} should be #{expected_type}"
      end
    end
  end
end
