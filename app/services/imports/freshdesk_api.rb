module Imports
  # Freshdesk v2 paginator. Conversations use their own paginated endpoint;
  # importing a ticket never assumes the first embedded page is complete.
  class FreshdeskApi < HttpSource
    ENTITIES = {
      "companies" => "/api/v2/companies",
      "contacts" => "/api/v2/contacts",
      "agents" => "/api/v2/agents"
    }.freeze

    MAX_TICKET_PAGES = 300

    def initialize(domain:, api_key:, per_page: 100, allow_insecure: false)
      base = domain.to_s.match?(%r{\Ahttps?://}i) ? domain : "https://#{domain}"
      super(base_url: base,
            headers: { "Authorization" => "Basic #{Base64.strict_encode64("#{api_key}:X")}" },
            allow_insecure: allow_insecure)
      @per_page = Integer(per_page)
      raise ArgumentError, "per_page must be between 1 and 100" unless (1..100).cover?(@per_page)
    end

    def each_entity(entity)
      entity = entity.to_s
      return tickets if entity == "tickets"
      return [].each unless ENTITIES.key?(entity)

      paginated(ENTITIES.fetch(entity))
    end

    def cursor_for(entity, row)
      return unless entity.to_s == "tickets"

      { "updated_at" => row["updated_at"], "id" => row["id"] }
    end

    private

    def tickets
      Enumerator.new do |yielder|
        query = {
          include: "requester,company,stats,description",
          updated_since: (watermark || Time.at(0)).utc.iso8601,
          order_by: "updated_at", order_type: "asc", per_page: @per_page
        }
        paginated("/api/v2/tickets", query: query, max_pages: MAX_TICKET_PAGES).each do |ticket|
          ticket["conversations"] = conversations(ticket.fetch("id"))
          yielder << ticket
        end
      end
    end

    def conversations(ticket_id)
      paginated("/api/v2/tickets/#{CGI.escape(ticket_id.to_s)}/conversations")
    end

    def paginated(path, query: {}, max_pages: nil)
      Enumerator.new do |yielder|
        page = 1
        loop do
          data, = get_json(path, query: query.merge(page: page, per_page: @per_page))
          rows = Array(data)
          rows.each { |row| yielder << row }
          if max_pages && page >= max_pages && rows.length >= @per_page
            raise Error, "Freshdesk ticket listing reached its #{max_pages}-page cap; use a bulk export or narrower time windows"
          end
          break if rows.length < @per_page

          page += 1
        end
      end
    end
  end
end
