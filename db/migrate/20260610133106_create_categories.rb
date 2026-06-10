class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :description
      t.boolean :ai_auto_resolve, null: false, default: false
      t.datetime :deleted_at

      t.timestamps

      t.index :name, unique: true, where: "deleted_at IS NULL"
      t.index :deleted_at
    end
  end
end
