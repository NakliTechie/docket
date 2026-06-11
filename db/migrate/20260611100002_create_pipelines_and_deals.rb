class CreatePipelinesAndDeals < ActiveRecord::Migration[8.1]
  def change
    create_table :pipelines do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :pipelines, :slug, unique: true, where: "deleted_at IS NULL"
    add_index :pipelines, :deleted_at

    create_table :pipeline_stages do |t|
      t.references :pipeline, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.integer :probability # 0-100, optional
      t.boolean :is_won, null: false, default: false
      t.boolean :is_lost, null: false, default: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :pipeline_stages, [ :pipeline_id, :position ]
    add_index :pipeline_stages, :deleted_at

    create_table :deals do |t|
      t.string :name, null: false
      t.references :pipeline, null: false, foreign_key: true
      t.references :pipeline_stage, null: false, foreign_key: true
      t.references :owner, foreign_key: { to_table: :users }
      t.references :contact, foreign_key: true
      t.references :organisation, foreign_key: true
      t.references :lead, foreign_key: true
      t.bigint :value_cents
      t.string :currency, null: false, default: "INR"
      t.date :expected_close_on
      t.integer :status, null: false, default: 0 # open
      t.datetime :closed_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :deals, :status
    add_index :deals, [ :pipeline_id, :pipeline_stage_id ]
    add_index :deals, :deleted_at
  end
end
