module Portal
  # Public, unauthenticated knowledge base (PG3): browse + search + read the
  # published, public articles. Internal and draft docs are never reachable
  # here — the scope (ReferenceDoc.public_kb) is the whole guard.
  class KnowledgeBaseController < BaseController
    def index
      @query = params[:q].to_s.strip
      @articles = Retrieval.search_articles(@query, scope: ReferenceDoc.public_kb)
    end

    def show
      @article = ReferenceDoc.public_kb.find_by!(slug: params[:slug])
    end
  end
end
