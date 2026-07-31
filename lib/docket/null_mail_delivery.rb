module Docket
  # A true sink for deployments without SMTP. Workflows must check
  # OutboundMail.available? and record an unavailable/skipped state before a
  # message reaches this adapter; the sink is the final egress fail-safe.
  class NullMailDelivery
    def initialize(*) = nil
    def deliver!(_mail) = true
  end
end
