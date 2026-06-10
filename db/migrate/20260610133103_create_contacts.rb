class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.string :external_id
      t.references :organisation, foreign_key: true
      t.string :preferred_language, null: false, default: "en"
      t.text :notes
      t.datetime :deleted_at

      t.timestamps

      t.index :email
      t.index :phone
      t.index :external_id, unique: true, where: "external_id IS NOT NULL AND deleted_at IS NULL"
      t.index :deleted_at
    end
  end
end
