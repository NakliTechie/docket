class CreateRecordScopes < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :record_read_scope, :integer, null: false, default: 5
    add_column :users, :record_write_scope, :integer, null: false, default: 5
    add_index :users, :record_read_scope
    add_index :users, :record_write_scope

    add_reference :cases, :owner, foreign_key: { to_table: :users }
    add_reference :contacts, :owner, foreign_key: { to_table: :users }
    add_reference :organisations, :owner, foreign_key: { to_table: :users }

    create_table :teams do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :teams, [ :tenant_id, :name ], unique: true,
              where: "deleted_at IS NULL"
    add_index :teams, :deleted_at

    create_table :team_memberships do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :team_memberships, [ :tenant_id, :team_id, :user_id ],
              unique: true, name: "index_team_memberships_on_tenant_team_user"

    create_table :account_memberships do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :organisation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :account_memberships, [ :tenant_id, :organisation_id, :user_id ],
              unique: true, name: "index_account_memberships_on_tenant_account_user"
  end
end
