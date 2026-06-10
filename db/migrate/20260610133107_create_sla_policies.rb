class CreateSlaPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :sla_policies do |t|
      t.string :name, null: false
      t.string :description
      t.datetime :deleted_at

      t.timestamps

      t.index :name, unique: true, where: "deleted_at IS NULL"
      t.index :deleted_at
    end

    create_table :sla_targets do |t|
      t.references :sla_policy, null: false, foreign_key: true
      t.integer :priority, null: false
      t.integer :first_response_minutes, null: false
      t.integer :resolution_minutes, null: false

      t.timestamps

      t.index [ :sla_policy_id, :priority ], unique: true
    end
  end
end
