class CreateApiCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at

      t.timestamps

      t.index :token_digest, unique: true
    end

    create_table :service_accounts do |t|
      t.string :name, null: false
      t.string :description
      t.string :client_id, null: false
      t.string :client_secret_digest, null: false
      t.json :scopes, null: false
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps

      t.index :client_id, unique: true
      t.index :deleted_at
    end

    create_table :oauth_access_tokens do |t|
      t.references :service_account, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.json :scopes, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      t.timestamps

      t.index :token_digest, unique: true
      t.index :expires_at
    end
  end
end
