class SequenceTracking
  class InvalidToken < StandardError; end

  PURPOSE = "sequence_click".freeze
  URL_PATTERN = %r{https?://[^\s<>"']+}.freeze

  def self.open!(tracking_token)
    with_delivery(tracking_token) do |delivery|
      delivery.record_open!
      delivery
    end
  end

  def self.click!(tracking_token, token)
    with_delivery(tracking_token) do |delivery|
      data = verifier.verify(token.to_s)
      raise InvalidToken unless data.fetch("delivery_id") == delivery.id

      destination = validated_destination(data.fetch("url"))
      delivery.record_click!
      destination
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature, KeyError, TypeError
    raise InvalidToken, "tracking link is invalid"
  end

  def self.open_url(delivery)
    url_helpers.sequence_tracking_open_url(
      token: delivery.tracking_token,
      **Docket::TenantUrl.options(tenant: delivery.tenant)
    )
  end

  def self.click_url(delivery, destination)
    destination = validated_destination(destination)
    token = verifier.generate({ "delivery_id" => delivery.id, "url" => destination })
    url_helpers.sequence_tracking_click_url(
      token: delivery.tracking_token,
      destination: token,
      **Docket::TenantUrl.options(tenant: delivery.tenant)
    )
  end

  def self.html_body(delivery)
    body = delivery.payload.fetch("body", "").to_s
    cursor = 0
    output = +""

    body.to_enum(:scan, URL_PATTERN).each do
      match = Regexp.last_match
      url, suffix = split_trailing_punctuation(match[0])
      output << ERB::Util.html_escape(body[cursor...match.begin(0)])
      output << %(<a href="#{ERB::Util.html_escape(click_url(delivery, url))}" rel="noopener noreferrer">)
      output << ERB::Util.html_escape(url)
      output << "</a>"
      output << ERB::Util.html_escape(suffix)
      cursor = match.end(0)
    end
    output << ERB::Util.html_escape(body[cursor..])
    output.gsub!("\n", "<br>\n")
    output.html_safe
  end

  def self.reply_address(delivery)
    configured = Setting.get("sequence_reply_domain").to_s.strip.downcase
    domain = configured.presence || outbound_domain
    return if domain.blank? || !domain.match?(/\A[a-z0-9.-]+\z/i)

    "sequence+#{delivery.tracking_token}@#{domain}"
  end

  def self.with_delivery(tracking_token)
    delivery = ActsAsTenant.without_tenant do
      SequenceDelivery.find_by!(tracking_token: tracking_token)
    end
    ActsAsTenant.with_tenant(delivery.tenant) { yield delivery }
  rescue ActiveRecord::RecordNotFound
    raise InvalidToken, "tracking token is invalid"
  end
  private_class_method :with_delivery

  def self.validated_destination(value)
    uri = URI.parse(value.to_s)
    raise InvalidToken unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?

    uri.to_s
  rescue URI::InvalidURIError
    raise InvalidToken, "tracking destination is invalid"
  end
  private_class_method :validated_destination

  def self.split_trailing_punctuation(value)
    trailing = value[/[.,;:!?]+\z/].to_s
    [ value.delete_suffix(trailing), trailing ]
  end
  private_class_method :split_trailing_punctuation

  def self.outbound_domain
    raw = Setting.get("outbound_email_from", ENV.fetch("DOCKET_MAIL_FROM", "no-reply@docket.local"))
    Mail::Address.new(raw.to_s).domain
  rescue Mail::Field::ParseError
    nil
  end
  private_class_method :outbound_domain

  def self.verifier = Rails.application.message_verifier(PURPOSE)
  private_class_method :verifier

  def self.url_helpers = Rails.application.routes.url_helpers
  private_class_method :url_helpers
end
