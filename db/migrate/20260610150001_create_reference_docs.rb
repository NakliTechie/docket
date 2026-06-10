class CreateReferenceDocs < ActiveRecord::Migration[8.1]
  def change
    create_table :reference_docs do |t|
      t.string :title, null: false
      t.text :body, null: false
      t.datetime :deleted_at

      t.timestamps

      t.index :title, unique: true, where: "deleted_at IS NULL"
      t.index :deleted_at
    end
  end
end
