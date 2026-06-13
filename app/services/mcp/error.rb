module Mcp
  # A JSON-RPC error: carries the numeric code the controller puts in the
  # `error` envelope (-32601 method not found, -32602 invalid params, …).
  class Error < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end
end
