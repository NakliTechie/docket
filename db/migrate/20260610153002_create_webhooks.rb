class CreateWebhooks < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoints do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.string :secret, null: false
      t.json :events, null: false
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
    end

    create_table :webhook_deliveries do |t|
      t.references :webhook_endpoint, null: false, foreign_key: true
      t.string :event, null: false
      t.json :payload, null: false
      t.integer :status, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.integer :response_code
      t.string :last_error
      t.datetime :delivered_at

      t.timestamps

      t.index [ :webhook_endpoint_id, :created_at ]
      t.index :status
    end
  end
end
