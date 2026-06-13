# Dependency-light grounding retrieval (handoff §4): Postgres full-text
# search where available, keyword overlap scoring on SQLite. Source: the
# admin-curated reference-doc knowledge base ONLY. No vector DB.
#
# Other citizens' resolved-case text is deliberately NOT a grounding source
# — pulling one case's personal details into another citizen's AI draft is
# a privacy leak. The knowledge base is the intended, reviewed source.
module Retrieval
  Result = Struct.new(:source, :title, :text, keyword_init: true)

  module_function

  # AI grounding — published docs only (drafts never ground), wrapped as
  # Results. Both visibilities ground; only the portal gates on public.
  def grounding_for(query, limit: 3)
    matched(ReferenceDoc.grounding, query, limit: limit * 2)
      .map { |doc| Result.new(source: "reference_doc", title: doc.title, text: doc.body.truncate(2000)) }
  end

  # Knowledge-base article search over a caller-chosen scope, returning the
  # ReferenceDoc records (so the portal/console can link by slug). A blank
  # query falls back to the scope's own default order.
  def search_articles(query, scope: ReferenceDoc.public_kb, limit: 20)
    return scope.limit(limit).to_a if query.blank?
    matched(scope, query, limit: limit)
  end

  # → Array of matching records from `scope`, ranked.
  def matched(scope, query, limit:)
    if postgres?
      scope.where("to_tsvector('simple', title || ' ' || body) @@ plainto_tsquery('simple', ?)", query)
           .limit(limit).to_a
    else
      keyword_match(scope, query, %w[title body], limit: limit)
    end
  end

  def keyword_match(scope, query, columns, limit:)
    terms = query.to_s.downcase.scan(/[\p{L}\d]{3,}/).uniq.first(8)
    return scope.none if terms.empty?

    clauses = terms.flat_map do |_term|
      columns.map { |column| "LOWER(#{column}) LIKE ?" }
    end
    values = terms.flat_map { |term| columns.map { "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" } }
    candidates = scope.where(clauses.join(" OR "), *values).limit(50)

    candidates.sort_by do |record|
      text = columns.map { |c| record.public_send(c).to_s }.join(" ").downcase
      -terms.count { |term| text.include?(term) }
    end.first(limit)
  end

  def postgres?
    ActiveRecord::Base.connection.adapter_name.match?(/postgresql/i)
  end
end
