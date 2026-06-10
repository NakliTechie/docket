class CreateQueueMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :queue_memberships do |t|
      t.references :queue, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps

      t.index [ :queue_id, :user_id ], unique: true
    end
  end
end
