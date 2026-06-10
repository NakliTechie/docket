class AddProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users do |t|
      t.string :name, null: false, default: ""
      t.integer :role, null: false, default: 2
      t.boolean :active, null: false, default: true
      t.string :locale
      t.datetime :deleted_at

      t.index :role
      t.index :deleted_at
    end
  end
end
