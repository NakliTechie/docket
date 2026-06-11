# Signed webhook POST with retry/backoff. Final failure marks the
# delivery failed; the admin delivery log shows every attempt.
class WebhookDeliveryJob < ApplicationJob
  queue_as :default

  class DeliveryError < StandardError; end

  retry_on DeliveryError, wait: :polynomially_longer, attempts: 6 do |job, error|
    delivery = job.arguments.first
    delivery.update!(status: :failed, last_error: error.message.truncate(250))
  end

  def perform(delivery)
    endpoint = delivery.webhook_endpoint
    return if endpoint.nil? || endpoint.deleted? || !endpoint.active?

    body = JSON.generate(delivery.payload)
    uri = URI.parse(endpoint.url)

    # SSRF guard at the egress point too (defense in depth): never connect
    # to a loopback / link-local / metadata target, and don't retry — it
    # will never become a valid destination.
    if (reason = Docket::OutboundUrl.blocked_reason(uri.host))
      delivery.update!(status: :failed, last_error: "blocked: #{reason}".truncate(250))
      return
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri.request_uri,
      "Content-Type" => "application/json",
      "User-Agent" => "Docket-Webhook",
      "X-Docket-Event" => delivery.event,
      "X-Docket-Delivery" => delivery.id.to_s,
      "X-Docket-Signature" => endpoint.sign(body))
    request.body = body

    response = http.request(request)
    delivery.increment(:attempts)
    if response.code.to_i.between?(200, 299)
      delivery.update!(status: :delivered, response_code: response.code.to_i, delivered_at: Time.current)
    else
      delivery.update!(status: :pending, response_code: response.code.to_i)
      raise DeliveryError, "endpoint returned #{response.code}"
    end
  rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError, SocketError => e
    delivery.increment(:attempts)
    delivery.update!(status: :pending, last_error: e.message.truncate(250))
    raise DeliveryError, e.message
  end
end
