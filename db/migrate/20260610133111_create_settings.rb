class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :key, null: false
      t.json :value

      t.timestamps

      t.index :key, unique: true
    end
  end
end
