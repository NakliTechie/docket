module Imports
  # Jira Cloud REST paginator using the current `/search/jql` cursor contract.
  # Issue comments are fetched through their independent pagination endpoint.
  class JiraApi < HttpSource
    SEARCH_FIELDS = %w[
      summary description issuetype priority status timeoriginalestimate
      aggregatetimeoriginalestimate duedate reporter assignee labels attachment
      created updated resolutiondate statuscategorychangedate project
    ].join(",").freeze

    def initialize(base_url:, email:, api_token:, page_size: 100, jql: nil,
                   allow_insecure: false)
      super(base_url: base_url,
            headers: { "Authorization" =>
              "Basic #{Base64.strict_encode64("#{email}:#{api_token}")}" },
            allow_insecure: allow_insecure)
      @page_size = Integer(page_size)
      @jql = jql.to_s.presence
      raise ArgumentError, "page_size must be between 1 and 100" unless (1..100).cover?(@page_size)
    end

    def each_entity(entity)
      return [].each if entity.to_s == "users"
      return issues if entity.to_s == "issues"

      [].each
    end

    def cursor_for(entity, row)
      return unless entity.to_s == "issues"

      { "updated_at" => row.dig("fields", "updated"), "id" => row["id"].presence || row["key"] }
    end

    private

    def issues
      Enumerator.new do |yielder|
        token = nil
        loop do
          query = { jql: effective_jql, maxResults: @page_size, fields: SEARCH_FIELDS }
          query[:nextPageToken] = token if token
          data, = get_json("/rest/api/3/search/jql", query: query)
          Array(data["issues"]).each do |issue|
            issue["fields"] ||= {}
            issue["fields"]["comment"] = { "comments" => comments(issue.fetch("key")) }
            yielder << issue
          end
          token = data["nextPageToken"].presence
          break if token.nil? || data["isLast"] == true
        end
      end
    end

    def comments(key)
      Enumerator.new do |yielder|
        offset = 0
        loop do
          data, = get_json("/rest/api/3/issue/#{CGI.escape(key.to_s)}/comment",
                           query: { startAt: offset, maxResults: @page_size })
          rows = Array(data["comments"])
          rows.each { |row| yielder << row }
          offset += rows.length
          break if rows.empty? || offset >= data["total"].to_i
        end
      end
    end

    def effective_jql
      clauses = []
      clauses << "(#{@jql})" if @jql
      clauses << %(updated >= "#{watermark.utc.strftime('%Y-%m-%d %H:%M')}") if watermark
      query = clauses.presence&.join(" AND ")
      [ query, "ORDER BY updated ASC, id ASC" ].compact.join(" ")
    end
  end
end
