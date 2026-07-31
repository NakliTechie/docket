module Imports
  # Incrementally reads one array from a JSON export without loading the file
  # into memory. It accepts a top-level array or a named top-level object field
  # such as Freshdesk's `tickets` and yields one parsed value at a time.
  class JsonRows
    class FormatError < StandardError; end

    CHUNK_SIZE = 64.kilobytes

    def self.from_file(path, root: nil)
      Enumerator.new do |yielder|
        File.open(path, "rb") { |io| new(io, root: root).each { |row| yielder << row } }
      end
    end

    def self.from_io(io, root: nil)
      Enumerator.new { |yielder| new(io, root: root).each { |row| yielder << row } }
    end

    def initialize(io, root: nil)
      @reader = Reader.new(io)
      @root = root&.to_s
    end

    def each
      return enum_for(:each) unless block_given?

      locate_array!
      loop do
        first = next_non_whitespace
        return if first == "]"
        raise FormatError, "unterminated JSON array" if first.nil?

        raw, delimiter = read_value(first)
        yield JSON.parse(raw)
        return if delimiter == "]"
      rescue JSON::ParserError => e
        raise FormatError, "invalid JSON row: #{e.message}"
      end
    end

    private

    def locate_array!
      first = next_non_whitespace
      return if first == "[" && @root.nil?
      if first != "{" || @root.nil?
        raise FormatError, @root ? "expected a top-level JSON object" : "expected a JSON array"
      end

      depth = 1
      loop do
        char = @reader.getc
        raise FormatError, "could not find array #{@root.inspect}" if char.nil?

        if char == '"'
          value = read_string
          if depth == 1 && value == @root
            colon = next_non_whitespace
            raise FormatError, "expected ':' after #{@root.inspect}" unless colon == ":"
            opening = next_non_whitespace
            raise FormatError, "#{@root.inspect} is not an array" unless opening == "["
            return
          end
        elsif char == "{"
          depth += 1
        elsif char == "}"
          depth -= 1
          raise FormatError, "could not find array #{@root.inspect}" if depth.zero?
        end
      end
    end

    def read_string
      raw = +'"'
      escaped = false
      loop do
        char = @reader.getc
        raise FormatError, "unterminated JSON string" if char.nil?

        raw << char
        if escaped
          escaped = false
        elsif char == "\\"
          escaped = true
        elsif char == '"'
          return JSON.parse(raw)
        end
      end
    end

    def read_value(first)
      raw = +first
      nesting = (first == "{" || first == "[") ? 1 : 0
      in_string = first == '"'
      escaped = false

      loop do
        char = @reader.getc
        raise FormatError, "unterminated JSON value" if char.nil?

        if in_string
          raw << char
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        if char == '"'
          in_string = true
          raw << char
        elsif char == "{" || char == "["
          nesting += 1
          raw << char
        elsif char == "}" || char == "]"
          if nesting.positive?
            nesting -= 1
            raw << char
          elsif char == "]"
            return [ raw.strip, "]" ]
          else
            raise FormatError, "unexpected JSON object terminator"
          end
        elsif nesting.zero? && (char == "," || char == "]")
          return [ raw.strip, char ]
        else
          raw << char
        end
      end
    end

    def next_non_whitespace
      loop do
        char = @reader.getc
        return char if char.nil? || !char.match?(/\s/)
      end
    end

    class Reader
      def initialize(io)
        @io = io
        @buffer = +""
        @offset = 0
      end

      def getc
        refill if @offset >= @buffer.bytesize
        return if @offset >= @buffer.bytesize

        char = @buffer.byteslice(@offset, 1)
        @offset += 1
        char
      end

      private

      def refill
        @buffer = @io.read(CHUNK_SIZE).to_s
        @offset = 0
      end
    end
  end
end
