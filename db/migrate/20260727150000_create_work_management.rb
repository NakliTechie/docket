class CreateWorkManagement < ActiveRecord::Migration[8.1]
  # The Work module (WM1): the Jira/Linear-class pillar, built on the same
  # platform seams as cases and deals — tenant-scoped, soft-deletable, audited.
  def change
    create_table :projects do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.string :key, null: false                 # uppercase, e.g. PEP
      t.string :name, null: false
      t.text :description
      t.references :lead, foreign_key: { to_table: :users }
      t.boolean :archived, null: false, default: false
      # The allocator for KEY-123. Bumped inside a row lock so two concurrent
      # creates can never mint the same number.
      t.integer :last_item_number, null: false, default: 0
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :projects, %i[tenant_id key], unique: true
    add_index :projects, :deleted_at

    create_table :workflow_states do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      # todo / in_progress / done — the reporting axis. Many named states can
      # share a category (e.g. "In review" and "In progress" are both work).
      t.integer :category, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :workflow_states, %i[project_id position]
    add_index :workflow_states, :deleted_at

    # Table lands here (not with the sprint BEHAVIOUR in WM3) purely so
    # work_items can carry its foreign key without a second migration.
    create_table :sprints do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :goal
      t.integer :status, null: false, default: 0  # planned/active/closed
      t.date :starts_on
      t.date :ends_on
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :sprints, :deleted_at

    create_table :work_items do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :project, null: false, foreign_key: true
      t.references :workflow_state, null: false, foreign_key: true
      t.integer :number, null: false             # per-project sequence -> KEY-123
      t.string :title, null: false
      t.text :description
      t.integer :kind, null: false, default: 0   # epic/story/task/bug
      t.integer :priority, null: false, default: 1
      t.references :assignee, foreign_key: { to_table: :users }
      t.references :reporter, foreign_key: { to_table: :users }
      t.references :parent, foreign_key: { to_table: :work_items }
      t.references :sprint, foreign_key: true, index: true
      t.json :labels
      t.decimal :estimate, precision: 6, scale: 2
      t.date :due_on
      t.integer :position, null: false, default: 0
      t.datetime :closed_at
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :work_items, %i[project_id number], unique: true
    add_index :work_items, :deleted_at

    create_table :work_comments do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :work_item, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :work_comments, :deleted_at

    create_table :work_watches do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :work_item, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :work_watches, %i[work_item_id user_id], unique: true

    create_table :project_memberships do |t|
      t.references :tenant, null: false, foreign_key: true, index: true
      t.references :project, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :project_memberships, %i[project_id user_id], unique: true
  end
end
