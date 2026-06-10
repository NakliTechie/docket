class CreateMacros < ActiveRecord::Migration[8.1]
  def change
    create_table :macros do |t|
      t.string :name, null: false
      t.text :body, null: false
      t.datetime :deleted_at

      t.timestamps

      t.index :name, unique: true, where: "deleted_at IS NULL"
      t.index :deleted_at
    end
  end
end
