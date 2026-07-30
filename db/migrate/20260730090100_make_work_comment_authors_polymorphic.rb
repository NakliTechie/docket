class MakeWorkCommentAuthorsPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_column :work_comments, :author_type, :string
    execute "UPDATE work_comments SET author_type = 'User'"
    change_column_null :work_comments, :author_type, false

    remove_foreign_key :work_comments, :users, column: :author_id
    remove_index :work_comments, :author_id
    add_index :work_comments, %i[author_type author_id]
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "service-account authors cannot be converted to users"
  end
end
