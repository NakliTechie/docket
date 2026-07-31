module Docket
  # Builds public origins for the tenant currently in scope. In a shared
  # deployment DOCKET_BASE_URL supplies the scheme/port while
  # DOCKET_BASE_DOMAIN supplies the DNS suffix; the tenant subdomain is never
  # borrowed from another request or from a global single-tenant URL.
  module TenantUrl
    module_function

    def base_url(tenant: ActsAsTenant.current_tenant)
      configured = Setting.get("app_base_url").to_s.strip if tenant
      return validated_origin(configured) if configured.present?

      uri = global_uri
      return uri.to_s.delete_suffix("/") unless Tenant.shared_deployment? && tenant&.subdomain.present?

      base_domain = ENV["DOCKET_BASE_DOMAIN"].to_s.strip.downcase.delete_prefix(".")
      base_domain = uri.host if base_domain.blank?
      uri.host = "#{tenant.subdomain}.#{base_domain}"
      uri.to_s.delete_suffix("/")
    end

    def options(tenant: ActsAsTenant.current_tenant)
      uri = URI.parse(base_url(tenant: tenant))
      {
        host: uri.host,
        protocol: uri.scheme,
        port: (uri.port unless uri.port == uri.default_port)
      }.compact
    end

    def global_uri
      raw = ENV["DOCKET_BASE_URL"].presence
      return URI.parse(validated_origin(raw)) if raw

      defaults = Rails.application.config.action_mailer.default_url_options || {}
      scheme = defaults[:protocol].presence || "http"
      host = defaults[:host].presence || ENV.fetch("DOCKET_HOST", "localhost")
      port = defaults[:port].presence || ENV["DOCKET_PORT"].presence
      URI.parse("#{scheme}://#{host}#{":#{port}" if port}")
    end

    def validated_origin(value)
      uri = URI.parse(value.to_s)
      origin_only = (uri.path.blank? || uri.path == "/") && uri.query.nil? && uri.fragment.nil?
      unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && origin_only
        raise ArgumentError, "public base URL must be an http(s) origin"
      end
      uri.to_s.delete_suffix("/")
    rescue URI::InvalidURIError
      raise ArgumentError, "public base URL must be an http(s) origin"
    end
    private_class_method :global_uri, :validated_origin
  end
end
