# Dependency-light grounding retrieval (handoff §4): Postgres full-text
# search where available, keyword overlap scoring on SQLite. Sources:
# (a) closed resolved cases, (b) reference docs. No vector DB.
module Retrieval
  Result = Struct.new(:source, :title, :text, keyword_init: true)

  module_function

  def grounding_for(query, limit: 3)
    docs = search_reference_docs(query, limit: limit)
    kase_results = search_closed_cases(query, limit: limit)
    (docs + kase_results).first(limit * 2)
  end

  def search_reference_docs(query, limit: 3)
    scope = ReferenceDoc.all
    matched =
      if postgres?
        scope.where("to_tsvector('simple', title || ' ' || body) @@ plainto_tsquery('simple', ?)", query)
             .limit(limit)
      else
        keyword_match(scope, query, %w[title body], limit: limit)
      end
    matched.map { |doc| Result.new(source: "reference_doc", title: doc.title, text: doc.body.truncate(2000)) }
  end

  def search_closed_cases(query, limit: 3)
    scope = Case.where(status: [ :resolved, :closed ])
    matched =
      if postgres?
        scope.where("to_tsvector('simple', subject || ' ' || COALESCE(description, '')) @@ plainto_tsquery('simple', ?)", query)
             .order(resolved_at: :desc).limit(limit)
      else
        keyword_match(scope, query, %w[subject description], limit: limit)
      end
    matched.map do |kase|
      resolution = kase.messages.where(kind: [ :public_reply, :agent_turn ], direction: :outbound)
                       .order(:created_at).last
      Result.new(
        source: "closed_case",
        title: kase.subject,
        text: [ kase.description, resolution && "Resolution: #{resolution.body}" ].compact.join("\n").truncate(2000)
      )
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
