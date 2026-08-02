module Portal
  # Public, unauthenticated knowledge base (PG3): browse + search + read the
  # published, public articles. Internal and draft docs are never reachable
  # here — the scope (ReferenceDoc.public_kb) is the whole guard.
  class KnowledgeBaseController < BaseController
    require_feature "service_desk.kb"
    def index
      @query = params[:q].to_s.strip
      @articles = Retrieval.search_articles(@query, scope: ReferenceDoc.public_kb)
    end

    def show
      @article = published_public_articles.find_by!(slug: params[:slug])
      @helpfulness = @article.helpfulness_summary
    end

    def rate
      article = published_public_articles.find_by!(slug: params[:slug])
      helpful = params[:helpful]
      raise ActionController::BadRequest unless %w[true false].include?(helpful)

      token = knowledge_visitor_token
      rating = article.reference_doc_ratings.find_or_initialize_by(
        reference_doc_version: article.current_version,
        visitor_token_digest: Digest::SHA256.hexdigest(token)
      )
      rating.helpful = helpful == "true"
      rating.save!
      redirect_to portal_kb_path(article.slug, anchor: "helpfulness"), notice: t(".recorded")
    end

    private

    def published_public_articles
      ReferenceDoc.status_published.visibility_public
    end

    def knowledge_visitor_token
      token = cookies.signed[:knowledge_visitor_token]
      return token if token.present?

      SecureRandom.hex(24).tap do |new_token|
        cookies.permanent.signed[:knowledge_visitor_token] = {
          value: new_token, httponly: true, same_site: :lax
        }
      end
    end
  end
end
