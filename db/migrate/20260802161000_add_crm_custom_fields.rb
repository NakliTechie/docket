class AddCrmCustomFields < ActiveRecord::Migration[8.1]
  def change
    json_type = connection.adapter_name.match?(/postgres/i) ? :jsonb : :json

    add_column :contacts, :custom_fields, json_type, null: false, default: {}
    add_column :leads, :custom_fields, json_type, null: false, default: {}
    add_column :deals, :custom_fields, json_type, null: false, default: {}
  end
end
