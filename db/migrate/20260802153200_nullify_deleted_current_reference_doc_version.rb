class NullifyDeletedCurrentReferenceDocVersion < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :reference_docs, column: :current_version_id
    add_foreign_key :reference_docs, :reference_doc_versions,
                    column: :current_version_id, on_delete: :nullify
  end
end
