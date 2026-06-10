module Docket
  # Admin-configurable CORS for the API only (handoff §5): the operator
  # allowlists their own web properties; everything else gets no CORS
  # headers at all. No external origins are ever default-allowed.
  class Cors
    ALLOWED_METHODS = "GET, POST, PATCH, PUT, DELETE, OPTIONS".freeze
    ALLOWED_HEADERS = "Authorization, Content-Type".freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      origin = env["HTTP_ORIGIN"]
      return @app.call(env) unless origin && env["PATH_INFO"].to_s.start_with?("/api/")

      if allowed?(origin)
        if env["REQUEST_METHOD"] == "OPTIONS"
          [ 204, cors_headers(origin).merge("Content-Length" => "0"), [] ]
        else
          status, headers, body = @app.call(env)
          [ status, headers.merge(cors_headers(origin)), body ]
        end
      elsif env["REQUEST_METHOD"] == "OPTIONS"
        [ 403, { "Content-Type" => "text/plain" }, [ "Origin not allowed" ] ]
      else
        @app.call(env)
      end
    end

    private

    def allowed?(origin)
      allowed_origins.include?(origin)
    rescue ActiveRecord::ActiveRecordError, ActiveRecord::NoDatabaseError
      false
    end

    def allowed_origins
      Setting.get("cors_allowed_origins").to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def cors_headers(origin)
      {
        "Access-Control-Allow-Origin" => origin,
        "Access-Control-Allow-Methods" => ALLOWED_METHODS,
        "Access-Control-Allow-Headers" => ALLOWED_HEADERS,
        "Access-Control-Max-Age" => "600",
        "Vary" => "Origin"
      }
    end
  end
end
