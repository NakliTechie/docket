class NullifyDeletedKnowledgeCategoryReferences < ActiveRecord::Migration[8.1]
  def change
    replace_with_nullifying_foreign_key(:reference_docs)
    replace_with_nullifying_foreign_key(:reference_doc_versions)
  end

  private

  def replace_with_nullifying_foreign_key(table)
    remove_foreign_key table, column: :knowledge_category_id
    add_foreign_key table, :knowledge_categories,
                    column: :knowledge_category_id, on_delete: :nullify
  end
end
