class CreateQueues < ActiveRecord::Migration[8.1]
  def change
    create_table :queues do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :description
      t.datetime :deleted_at

      t.timestamps

      t.index :name, unique: true, where: "deleted_at IS NULL"
      t.index :slug, unique: true, where: "deleted_at IS NULL"
      t.index :deleted_at
    end
  end
end
