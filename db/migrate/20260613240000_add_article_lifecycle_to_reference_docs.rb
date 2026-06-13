# PG3 — promote the grounding corpus to a knowledge-base article product.
# status: draft|published — only published docs ground the AI / show anywhere.
# visibility: internal|public — only public+published reach the citizen portal.
# slug: stable portal URL key. category: optional grouping.
#
# Default status = published so the existing corpus keeps grounding exactly as
# before (zero regression); visibility defaults to internal (nothing becomes
# public without a deliberate flip). Draft is an explicit opt-in.
class AddArticleLifecycleToReferenceDocs < ActiveRecord::Migration[8.1]
  def change
    add_column :reference_docs, :status, :integer, null: false, default: 1
    add_column :reference_docs, :visibility, :integer, null: false, default: 0
    add_column :reference_docs, :slug, :string
    add_reference :reference_docs, :category, foreign_key: true, null: true
    add_index :reference_docs, [ :tenant_id, :slug ], unique: true,
              where: "slug IS NOT NULL AND deleted_at IS NULL",
              name: "index_reference_docs_on_tenant_id_and_slug"
  end
end
