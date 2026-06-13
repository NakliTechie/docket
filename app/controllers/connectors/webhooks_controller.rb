module Connectors
  # Inbound connector webhook. Two shapes share one endpoint:
  #   • A sync ping ("data changed, pull now") — HMAC-verified with the
  #     connector's per-endpoint secret, enqueues a sync.
  #   • An inbound message (omnichannel providers, PG2) — verified with the
  #     provider's own scheme, turned into case activity via Connectors::Inbound.
  # Unauthenticated by design (the signature IS the auth). The connector is
  # found tenant-scoped, so a webhook only ever touches its own tenant's data.
  class WebhooksController < ApplicationController
    allow_unauthenticated_access
    skip_before_action :verify_authenticity_token

    # GET — platform webhook-URL verification handshake (e.g. WhatsApp Cloud
    # echoes hub.challenge once the verify token matches).
    def verify
      connector = Connector.active.find_by(id: params[:id])
      return head :not_found unless connector&.ingests?

      challenge = connector.provider_instance.verification_challenge(request.query_parameters)
      challenge.present? ? render(plain: challenge) : head(:forbidden)
    end

    def create
      connector = Connector.active.find_by(id: params[:id])
      return head :not_found unless connector

      if connector.ingests?
        return head :unauthorized unless connector.provider_instance.inbound_authentic?(request)
        Connectors::Inbound.process(connector, inbound_payload)
        head :ok
      else
        return head :unauthorized unless valid_signature?(connector)
        ConnectorSyncJob.perform_later(connector.id, trigger: "webhook")
        head :accepted
      end
    end

    private

    def inbound_payload
      JSON.parse(request.raw_post.presence || "{}")
    rescue JSON::ParserError
      {}
    end

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
