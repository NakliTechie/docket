# openid_connect 2.5 builds discovery endpoints through process-global
# SWD/WebFinger URL builders, defaulting to HTTPS and discarding the issuer's
# scheme. Flipping those globals for a local HTTP IdP makes concurrent HTTPS
# tenants use HTTP too. Preserve the scheme on each discovery resource/request
# instead, so one tenant's issuer can never affect another's.
module Docket
  module OidcDiscoveryScheme
    module ProviderConfigResource
      def initialize(uri)
        @docket_url_builder = uri.scheme == "http" ? URI::HTTP : URI::HTTPS
        super
      end

      def endpoint
        @docket_url_builder.build([ nil, host, port, path, nil, nil ])
      rescue URI::Error => e
        raise SWD::Exception, e.message
      end
    end

    module WebFingerRequest
      def initialize(resource, ...)
        uri = URI.parse(resource.to_s)
        @docket_url_builder = uri.scheme == "http" ? URI::HTTP : URI::HTTPS
        super
      rescue URI::InvalidURIError
        @docket_url_builder = URI::HTTPS
        super
      end

      private

      def endpoint
        host, port = host_and_port
        @docket_url_builder.build([ nil, host, port, "/.well-known/webfinger", query_string, nil ])
      end
    end
  end
end

OpenIDConnect::Discovery::Provider::Config::Resource.prepend(
  Docket::OidcDiscoveryScheme::ProviderConfigResource
)
WebFinger::Request.prepend(Docket::OidcDiscoveryScheme::WebFingerRequest)
