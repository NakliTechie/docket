class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :case, null: false, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.integer :direction, null: false, default: 0
      t.references :author, polymorphic: true
      t.string :subject
      t.text :body, null: false
      t.string :email_message_id
      t.json :metadata
      t.datetime :deleted_at

      t.timestamps

      t.index [ :case_id, :created_at ]
      t.index :email_message_id
      t.index :deleted_at
    end
  end
end
