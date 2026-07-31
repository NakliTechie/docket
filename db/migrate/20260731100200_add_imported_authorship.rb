class AddImportedAuthorship < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :source_author_name, :string
    add_column :work_comments, :source_author_name, :string
    change_column_null :work_comments, :author_type, true
    change_column_null :work_comments, :author_id, true
  end
end
