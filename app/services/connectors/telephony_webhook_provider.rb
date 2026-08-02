module Connectors
  # Provider-neutral inbound adapter for PBX/IVR systems. Operators sign JSON
  # with the connector's per-endpoint HMAC secret, then map their provider's
  # callback into this small stable envelope.
  class TelephonyWebhookProvider < Provider
    def self.descriptor
      Descriptor.new(
        key: "telephony_webhook", name: "Telephony / IVR webhook",
        category: "Communications", auth: :none, config_fields: [],
        credential_fields: [], syncs: false
      )
    end

    def self.ingests_calls? = true

    def ingest_calls(payload)
      calls = if payload.is_a?(Hash) && payload["calls"].is_a?(Array)
        payload["calls"]
      elsif payload.is_a?(Hash)
        [ payload ]
      else
        Array(payload)
      end
      calls.filter_map { |call| normalize(call) }
    end

    def fetch = []

    private

    def normalize(call)
      return unless call.is_a?(Hash)

      provider_call_id = value(call, "provider_call_id", "call_id", "id")
      from_number = value(call, "from_number", "from", "caller", "From")
      return if provider_call_id.blank? || from_number.blank?

      {
        provider_call_id: provider_call_id.truncate(255),
        from_number: from_number.truncate(64),
        to_number: value(call, "to_number", "to", "called", "To")&.truncate(64),
        status: value(call, "status", "state").presence || "received",
        recording_url: value(call, "recording_url", "recording")&.truncate(2_000),
        duration_seconds: value(call, "duration_seconds", "duration"),
        ivr_answers: call["ivr_answers"].is_a?(Hash) ? call["ivr_answers"] : {},
        transcript: call["transcript"].to_s.truncate(100_000).presence,
        started_at: call["started_at"], ended_at: call["ended_at"],
        metadata: call["metadata"].is_a?(Hash) ? call["metadata"] : {}
      }
    end

    def value(hash, *keys)
      keys.filter_map { |key| hash[key] }.first.to_s.strip.presence
    end
  end
end
