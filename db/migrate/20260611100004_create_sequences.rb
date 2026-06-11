class CreateSequences < ActiveRecord::Migration[8.1]
  def change
    create_table :sequences do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :sequences, :deleted_at

    create_table :sequence_steps do |t|
      t.references :sequence, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.integer :delay_days, null: false, default: 0
      t.integer :channel, null: false, default: 0 # email
      t.string :subject
      t.text :body
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :sequence_steps, [ :sequence_id, :position ]
    add_index :sequence_steps, :deleted_at

    create_table :sequence_enrollments do |t|
      t.references :sequence, null: false, foreign_key: true
      t.references :enrollable, polymorphic: true, null: false
      t.integer :current_step_position, null: false, default: 0
      t.integer :status, null: false, default: 0 # active
      t.datetime :next_run_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :sequence_enrollments, [ :status, :next_run_at ]
    add_index :sequence_enrollments, :deleted_at
  end
end
