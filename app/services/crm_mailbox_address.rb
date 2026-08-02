class CrmMailboxAddress
  PURPOSE = "crm_mailbox".freeze
  LOCAL_PATTERN = /\Acrm\+([^@]+)@/i
  TYPE_KEYS = { "contact" => "Contact", "lead" => "Lead", "deal" => "Deal" }.freeze

  class InvalidAddress < StandardError; end

  def self.address_for(record)
    domain = configured_domain
    return if domain.blank?

    payload = [ record.tenant_id.to_s(36), record.class.name.downcase, record.id.to_s(36) ].join("-")
    signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, payload).first(24)
    token = "#{payload}-#{signature}"
    "crm+#{token}@#{domain}"
  end

  def self.record_for(recipients)
    token = Array(recipients).filter_map { |recipient| recipient.to_s[LOCAL_PATTERN, 1] }.first
    return unless token

    tenant_id, type_key, subject_id, supplied_signature = token.downcase.split("-", 4)
    type = TYPE_KEYS[type_key]
    payload = [ tenant_id, type_key, subject_id ].join("-")
    expected_signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, payload).first(24)
    valid_signature = supplied_signature.present? &&
                      ActiveSupport::SecurityUtils.secure_compare(supplied_signature, expected_signature)
    raise InvalidAddress unless type && valid_signature

    record = ActsAsTenant.without_tenant { type.constantize.unscoped.find(subject_id.to_i(36)) }
    raise InvalidAddress unless record.tenant_id == tenant_id.to_i(36) && !record.deleted?

    record
  rescue ActiveRecord::RecordNotFound, TypeError, NameError
    raise InvalidAddress, "CRM mailbox address is invalid"
  end

  def self.configured_domain
    value = Setting.get("sequence_reply_domain").to_s.strip.downcase
    value = outbound_domain if value.blank?
    value if value.match?(/\A[a-z0-9.-]+\z/i)
  end
  private_class_method :configured_domain

  def self.outbound_domain
    raw = Setting.get("outbound_email_from", ENV.fetch("DOCKET_MAIL_FROM", "no-reply@docket.local"))
    Mail::Address.new(raw.to_s).domain
  rescue Mail::Field::ParseError
    nil
  end
  private_class_method :outbound_domain

  def self.signing_key = Rails.application.key_generator.generate_key(PURPOSE, 32)
  private_class_method :signing_key
end
