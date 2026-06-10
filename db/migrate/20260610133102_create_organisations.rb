class CreateOrganisations < ActiveRecord::Migration[8.1]
  def change
    create_table :organisations do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "department"
      t.string :external_ref
      t.text :notes
      t.datetime :deleted_at

      t.timestamps

      t.index :name, unique: true, where: "deleted_at IS NULL"
      t.index :external_ref
      t.index :deleted_at
    end
  end
end
