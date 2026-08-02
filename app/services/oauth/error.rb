module Oauth
  class Error < StandardError
    attr_reader :code, :status, :description

    def initialize(code, description = nil, status: :bad_request)
      @code = code
      @description = description
      @status = status
      super(description || code)
    end
  end
end
