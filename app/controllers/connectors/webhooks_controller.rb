module Connectors
  # Inbound webhook ping: an external system tells Docket "data changed,
  # pull now". HMAC-verified with the connector's per-endpoint secret; a
  # valid ping enqueues a sync. Unauthenticated by design (the signature
  # IS the auth).
  class WebhooksController < ApplicationController
    allow_unauthenticated_access
    skip_before_action :verify_authenticity_token

    def create
      connector = Connector.active.find_by(id: params[:id])
      return head :not_found unless connector
      return head :unauthorized unless valid_signature?(connector)

      ConnectorSyncJob.perform_later(connector.id, trigger: "webhook")
      head :accepted
    end

    private

    def skip_pundit?
      true
    end

    def valid_signature?(connector)
      provided = request.headers["X-Docket-Signature"].to_s
      expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", connector.webhook_secret.to_s, request.raw_post)}"
      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end
  end
end
