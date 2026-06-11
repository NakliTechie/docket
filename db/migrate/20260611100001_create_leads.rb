class CreateLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :leads do |t|
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.string :company_name
      t.integer :source, null: false, default: 2  # manual
      t.integer :status, null: false, default: 0   # new
      t.references :owner, foreign_key: { to_table: :users }
      t.references :contact, foreign_key: true
      t.bigint :value_estimate_cents
      t.text :notes
      t.datetime :converted_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :leads, :status
    add_index :leads, :email
    add_index :leads, :deleted_at
  end
end
