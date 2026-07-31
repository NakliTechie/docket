class RenameImportRunErrors < ActiveRecord::Migration[8.1]
  def change
    rename_column :import_runs, :errors, :error_messages
  end
end
