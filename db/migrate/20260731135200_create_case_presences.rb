class CreateCasePresences < ActiveRecord::Migration[8.1]
  def change
    create_table :case_presences do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :case, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :last_seen_at, null: false
      t.timestamps
    end
    add_index :case_presences, %i[tenant_id case_id user_id], unique: true
    add_index :case_presences, %i[tenant_id case_id last_seen_at]
  end
end
