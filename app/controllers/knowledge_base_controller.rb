# In-console knowledge-base search (PG3): staff search the published corpus
# (both visibilities — the internal KB is for agents) and insert an article
# link/snippet into a reply. Renders a turbo-frame the case workspace swaps in.
class KnowledgeBaseController < ApplicationController
  def search
    authorize :knowledge_base, policy_class: KnowledgeBasePolicy
    @query = params[:q].to_s.strip
    @articles = @query.present? ? Retrieval.search_articles(@query, scope: ReferenceDoc.grounding, limit: 8) : []
  end
end
