class CreateServiceAccountConnectorGrants < ActiveRecord::Migration[8.1]
  def up
    create_table :service_account_connector_grants do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :service_account, null: false, foreign_key: { on_delete: :cascade }
      t.references :connector, null: false, foreign_key: { on_delete: :cascade }
      t.json :actions, null: false, default: []
      t.timestamps
    end
    add_index :service_account_connector_grants,
              %i[tenant_id service_account_id connector_id],
              unique: true,
              name: "index_service_account_connector_grants_uniqueness"

    backfill_existing_invoke_authority
  end

  def down
    drop_table :service_account_connector_grants
  end

  private

  def backfill_existing_invoke_authority
    account_class = Class.new(ActiveRecord::Base) do
      self.table_name = "service_accounts"
    end
    connector_class = Class.new(ActiveRecord::Base) do
      self.table_name = "connectors"
    end
    grant_class = Class.new(ActiveRecord::Base) do
      self.table_name = "service_account_connector_grants"
    end

    account_class.where(deleted_at: nil).find_each do |account|
      next unless Array(account.scopes).map(&:to_s).include?("connectors:invoke")

      connector_class.where(tenant_id: account.tenant_id, deleted_at: nil).find_each do |connector|
        actions = Array(connector.enabled_actions).map(&:to_s).reject(&:blank?).uniq
        next if actions.empty?

        grant_class.create!(tenant_id: account.tenant_id, service_account_id: account.id,
                            connector_id: connector.id, actions: actions,
                            created_at: Time.current, updated_at: Time.current)
      end
    end
  end
end
