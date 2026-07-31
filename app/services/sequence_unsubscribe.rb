class SequenceUnsubscribe
  class InvalidToken < StandardError; end
  Result = Data.define(:tenant, :target, :cancelled_enrollments)
  PURPOSE = "sequence_unsubscribe".freeze
  ENROLLABLE_TYPES = { "Contact" => Contact, "Lead" => Lead }.freeze

  def self.token_for(target)
    verifier.generate(
      { "tenant_id" => target.tenant_id, "type" => target.class.name, "id" => target.id,
        "email_sha256" => email_digest(target.email) }
    )
  end

  def self.url_for(target)
    path = Rails.application.routes.url_helpers.sequence_unsubscribe_path(token: token_for(target))
    URI.join(Sso.base_url.end_with?("/") ? Sso.base_url : "#{Sso.base_url}/", path.delete_prefix("/")).to_s
  end

  def self.resolve(token)
    data = verifier.verify(token.to_s)
    model = ENROLLABLE_TYPES.fetch(data.fetch("type"))
    tenant = Tenant.find(data.fetch("tenant_id"))
    target = ActsAsTenant.with_tenant(tenant) { model.with_deleted.find(data.fetch("id")) }
    expected = email_digest(target.email)
    supplied = data.fetch("email_sha256").to_s
    unless expected.bytesize == supplied.bytesize &&
           ActiveSupport::SecurityUtils.secure_compare(expected, supplied)
      raise InvalidToken, "email no longer matches"
    end

    Result.new(tenant: tenant, target: target, cancelled_enrollments: 0)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound,
         KeyError, TypeError
    raise InvalidToken, "unsubscribe link is invalid"
  end

  def self.call(token)
    resolved = resolve(token)
    cancelled = ActsAsTenant.with_tenant(resolved.tenant) do
      ApplicationRecord.transaction do
        resolved.target.with_lock do
          resolved.target.update!(email_consent: false, email_unsubscribed_at: Time.current)
          enrollments = SequenceEnrollment.where(enrollable: resolved.target)
          count = enrollments.status_active.count
          enrollments.status_active.find_each(&:cancel!)
          SequenceDelivery.status_pending.where(sequence_enrollment: enrollments, channel: "email")
                          .update_all(status: SequenceDelivery.statuses.fetch("skipped"),
                                      last_error: "email consent withdrawn", updated_at: Time.current)
          count
        end
      end
    end
    Result.new(tenant: resolved.tenant, target: resolved.target,
               cancelled_enrollments: cancelled)
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end
  private_class_method :verifier

  def self.email_digest(email)
    Digest::SHA256.hexdigest(email.to_s.strip.downcase)
  end
  private_class_method :email_digest
end
