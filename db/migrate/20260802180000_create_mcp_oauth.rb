class CreateMcpOauth < ActiveRecord::Migration[8.1]
  def change
    create_oauth_clients
    create_authorization_codes
    create_refresh_tokens
    extend_access_tokens
  end

  private

  def create_oauth_clients
    create_table :oauth_clients do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.string :client_id, null: false
      t.string :client_secret_digest
      t.string :client_name, null: false
      t.column :redirect_uris, json_type, null: false, default: []
      t.column :grant_types, json_type, null: false, default: []
      t.column :response_types, json_type, null: false, default: []
      t.string :token_endpoint_auth_method, null: false, default: "none"
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :oauth_clients, :client_id, unique: true
    add_index :oauth_clients, %i[tenant_id active]
  end

  def create_authorization_codes
    create_table :oauth_authorization_codes do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :oauth_client, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :code_digest, null: false
      t.string :redirect_uri, null: false
      t.string :code_challenge, null: false
      t.column :scopes, json_type, null: false, default: []
      t.string :resource, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :oauth_authorization_codes, :code_digest, unique: true
    add_index :oauth_authorization_codes, :expires_at
  end

  def create_refresh_tokens
    create_table :oauth_refresh_tokens do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :oauth_client, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false
      t.column :scopes, json_type, null: false, default: []
      t.string :resource, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :oauth_refresh_tokens, :token_digest, unique: true
    add_index :oauth_refresh_tokens, :expires_at
  end

  def extend_access_tokens
    change_column_null :oauth_access_tokens, :service_account_id, true
    add_reference :oauth_access_tokens, :user, null: true,
                  foreign_key: { on_delete: :cascade }
    add_reference :oauth_access_tokens, :oauth_client, null: true,
                  foreign_key: { on_delete: :cascade }
    add_column :oauth_access_tokens, :resource, :string
    add_check_constraint :oauth_access_tokens,
                         "(service_account_id IS NOT NULL AND user_id IS NULL) OR " \
                         "(service_account_id IS NULL AND user_id IS NOT NULL AND oauth_client_id IS NOT NULL AND resource IS NOT NULL)",
                         name: "oauth_access_tokens_one_principal"
  end

  def json_type
    connection.adapter_name.match?(/postgres/i) ? :jsonb : :json
  end
end
