class EnforceUniqueRootKnowledgeCategories < ActiveRecord::Migration[8.1]
  def change
    add_index :knowledge_categories, [ :tenant_id, :name ], unique: true,
              where: "parent_id IS NULL AND deleted_at IS NULL",
              name: "index_knowledge_categories_on_root_name"
  end
end
