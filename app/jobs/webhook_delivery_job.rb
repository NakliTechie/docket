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
    code = response.code.to_i
    if code.between?(200, 299)
      delivery.update!(status: :delivered, response_code: code, delivered_at: Time.current)
    elsif retryable_status?(code)
      delivery.update!(status: :pending, response_code: code)
      raise DeliveryError, "endpoint returned #{code}"
    else
      # 3xx (Net::HTTP doesn't follow redirects) and 4xx (except 408/429) won't
      # succeed on retry — fail fast instead of burning the retry budget (L7).
      delivery.update!(status: :failed, response_code: code, last_error: "endpoint returned #{code}")
    end
  rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, IOError, SocketError => e
    delivery.increment(:attempts)
    delivery.update!(status: :pending, last_error: e.message.truncate(250))
    raise DeliveryError, e.message
  end

  private

  # Transient server-side conditions worth retrying; 3xx/4xx are the client's
  # to fix (permanent), except the explicit "try later" codes.
  def retryable_status?(code)
    code >= 500 || [ 408, 429 ].include?(code)
  end
end
