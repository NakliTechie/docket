module Imports
  # Normalises small in-memory fixtures, streaming export files, and paginated
  # API adapters behind the same row enumerator contract.
  class Input
    def initialize(payload: nil, file: nil, source: nil, bare_entity:)
      @file = file
      @source = source
      @bare_entity = bare_entity.to_s
      @payload = parse(payload) unless payload.nil?
      raise ArgumentError, "provide exactly one of payload, file, or source" unless inputs == 1
    end

    def rows(entity, optional: false)
      entity = entity.to_s
      return @source.each_entity(entity) if @source
      return file_rows(entity, optional: optional) if @file

      value = if @payload.is_a?(Array)
        entity == @bare_entity ? @payload : []
      else
        @payload[entity] || @payload[entity.to_sym] || []
      end
      Array(value).each
    end

    private

    def inputs
      [ @payload, @file, @source ].count { |value| !value.nil? }
    end

    def parse(payload)
      payload.is_a?(String) ? JSON.parse(payload) : payload
    rescue JSON::ParserError => e
      raise JsonRows::FormatError, "could not parse the export: #{e.message}"
    end

    def file_rows(entity, optional:)
      rows = JsonRows.from_file(@file, root: entity)
      return rows unless optional

      Enumerator.new do |yielder|
        rows.each { |row| yielder << row }
      rescue JsonRows::FormatError => e
        raise unless e.message.start_with?("could not find array")
      end
    end
  end
end
