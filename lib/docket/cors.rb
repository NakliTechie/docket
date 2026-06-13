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

      if allowed?(origin, env)
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

    def allowed?(origin, env)
      allowed_origins(env).include?(origin)
    rescue ActiveRecord::ActiveRecordError # NoDatabaseError is a subclass — covered.
      false
    end

    # CORS runs before TenantResolution, so resolve the tenant from the host
    # here and read the allowlist in that tenant's scope — otherwise every
    # tenant shares the global setting and one tenant's origin is honored on
    # all subdomains (M1). Unknown subdomain (shared) → no app → no CORS.
    def allowed_origins(env)
      tenant = Tenant.resolve_by_subdomain(ActionDispatch::Request.new(env).subdomain)
      return [] if tenant.nil?
      ActsAsTenant.with_tenant(tenant) do
        Setting.get("cors_allowed_origins").to_s.split(",").map(&:strip).reject(&:blank?)
      end
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
