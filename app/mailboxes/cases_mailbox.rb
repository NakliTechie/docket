# Inbound email intake (handoff §3): a tracking ID in the subject
# threads the mail onto its case — but only when the sender matches the
# case contact (anti-spoofing); anything else opens a new case.
# Attachments ride Active Storage under the same allowlist as every
# other upload surface.
class CasesMailbox < ApplicationMailbox
  TRACKING_ID_PATTERN = /DKT-[A-Z2-9]{4}-[A-Z2-9]{4}/

  before_processing :ensure_sender

  def process
    crm_target = CrmMailboxAddress.record_for(recipients)
    tenant = crm_target&.tenant || resolve_tenant
    inbound_email.update_column(:tenant_id, tenant.id)

    ActsAsTenant.with_tenant(tenant) do
      if crm_target
        process_crm_message(crm_target)
        return
      end

      if sequence_reply_delivery
        process_sequence_reply(sequence_reply_delivery)
        return
      end

      # A tenant without the service desk has no cases to open. Bounce rather
      # than silently manufacturing one — inbound mail was the last unguarded
      # way into the desk.
      return bounced! unless tenant.feature?("service_desk")

      if existing_case && sender_matches?(existing_case)
        thread_onto(existing_case)
      else
        open_new_case
      end
    end
  rescue CrmMailboxAddress::InvalidAddress
    bounced!
  end

  private

  # Inbound mail has no request host, so the tenant comes from elsewhere:
  # isolated deploys have one (the singleton); shared deploys read it from the
  # recipient's subdomain (e.g. support@acme.docket.app → acme). The
  # per-tenant inbound-address scheme is operator-configured; this is the v1.
  def resolve_tenant
    return Tenant.primary if Tenant.isolated_deployment?

    sub = recipients.filter_map { |r| r.split("@").last&.split(".")&.first }.find(&:present?)
    Tenant.active.find_by(subdomain: sub) ||
      raise(ActiveRecord::RecordNotFound, "no tenant for inbound recipient #{sub.inspect}")
  end

  def recipients
    header_recipients = %w[X-Original-To Delivered-To Envelope-To X-Envelope-To].flat_map do |name|
      Array(mail[name]&.addresses)
    end
    (Array(mail.to) + Array(mail.cc) + Array(mail.bcc) + header_recipients)
      .compact.map { |address| address.to_s.strip.downcase }
  end

  def process_crm_message(target)
    return bounced! unless target.tenant.feature?("crm")
    return if CrmMessage.with_deleted.exists?(email_message_id: mail.message_id)

    customer_email = CrmConversation.recipient_email(target).to_s.downcase.presence
    author = User.active.find_by(email_address: sender_email)
    direction = author ? :outbound : :inbound
    return bounced! unless author || customer_email&.casecmp?(sender_email)

    message = CrmMessage.new(
      subject: target,
      author: author,
      channel: :email,
      direction: direction,
      delivery_status: :recorded,
      sender_email: sender_email,
      recipient_email: direction == :outbound ? customer_email : CrmMailboxAddress.address_for(target),
      subject_line: mail.subject,
      email_message_id: mail.message_id,
      body: extract_body.presence || "(empty message)",
      occurred_at: Time.current,
      metadata: { "ingress" => "bcc" }
    )
    attach_files(message)
    message.save!
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def sequence_reply_delivery
    return @sequence_reply_delivery if defined?(@sequence_reply_delivery)

    token = recipients.filter_map { |recipient| recipient[/\Asequence\+([^@]+)@/, 1] }.first
    delivery = token && SequenceDelivery.where(channel: "email")
                                        .find_by("LOWER(tracking_token) = ?", token.downcase)
    @sequence_reply_delivery = delivery if delivery&.recipient.to_s.casecmp?(sender_email.to_s)
  end

  def process_sequence_reply(delivery)
    enrollment = delivery.sequence_enrollment
    delivery.record_reply!
    enrollment.cancel! if enrollment.status_active?
    Activity.create!(
      subject: enrollment.enrollable,
      owner: enrollment.enrolment_owner,
      kind: :email,
      status: :done,
      completed_at: Time.current,
      title: mail.subject.presence || "Sequence reply",
      body: extract_body.presence || "(empty message)"
    )
  end

  def ensure_sender
    # Bounce unless the From yields a genuinely valid email. A malformed
    # header otherwise slips a garbage "address" through (e.g. "p" from
    # "plain text"), which then fails Contact's email validation and 500s
    # the intake job (M15).
    bounced! unless sender_email&.match?(URI::MailTo::EMAIL_REGEXP)
  end

  def sender_email
    return @sender_email if defined?(@sender_email)
    # A malformed From header makes the mail gem raise on parse — treat it
    # as no usable sender (→ bounced!) rather than crashing the job (M15).
    @sender_email = begin
      mail.from&.first.to_s.strip.downcase.presence
    rescue StandardError
      nil
    end
  end

  def sender_name
    (mail[:from]&.display_names&.first.presence || sender_email.to_s.split("@").first)
  rescue StandardError
    sender_email.to_s.split("@").first
  end

  def existing_case
    return @existing_case if defined?(@existing_case)
    tracking_id = mail.subject.to_s[TRACKING_ID_PATTERN]
    @existing_case = tracking_id && Case.find_by(tracking_id: tracking_id)&.canonical_record
  end

  def sender_matches?(kase)
    kase.contact.email.present? && kase.contact.email == sender_email
  end

  def thread_onto(kase)
    create_message(kase, kase.contact)
  end

  def open_new_case
    contact = Contact.find_by(email: sender_email) ||
              Contact.create!(name: sender_name, email: sender_email)
    kase = Case.create!(
      subject: mail.subject.presence || I18n.t("cases.email_intake.no_subject"),
      contact: contact,
      channel: :email,
      queue_id: Setting.get("default_queue_id")
    )
    create_message(kase, contact)
  end

  def create_message(kase, contact)
    message = kase.messages.build(
      kind: :public_reply,
      direction: :inbound,
      author: contact,
      subject: mail.subject,
      email_message_id: mail.message_id,
      body: extract_body.presence || "(empty message)"
    )
    attach_files(message)
    message.save!
  end

  def extract_body
    part = mail.text_part || (mail.content_type.to_s.start_with?("text/plain") ? mail : nil)
    if part
      decoded(part)
    elsif mail.html_part
      strip_html(decoded(mail.html_part))
    elsif !mail.multipart?
      strip_html(decoded(mail))
    end
  end

  def decoded(part)
    body = part.decoded
    body = body.force_encoding(part.charset.presence || "UTF-8") if body.encoding == Encoding::ASCII_8BIT
    body.encode("UTF-8", invalid: :replace, undef: :replace)
  rescue StandardError
    # Reuse the bytes already decoded above rather than re-invoking
    # part.decoded (which would just raise again if that was the failure).
    body.to_s.scrub
  end

  # Prune (not just strip) so script/style CONTENT goes too.
  def strip_html(html)
    Loofah.html5_fragment(html.to_s).scrub!(:prune).text(encode_special_chars: false)
          .gsub(/\n{3,}/, "\n\n").strip
  end

  def attach_files(message)
    mail.attachments.first(AttachableValidation::MAX_FILES).each do |attachment|
      next unless AttachableValidation::ALLOWED_CONTENT_TYPES.include?(attachment.content_type&.split(";")&.first)
      next if attachment.decoded.bytesize > AttachableValidation::MAX_FILE_SIZE
      message.files.attach(
        io: StringIO.new(attachment.decoded),
        filename: attachment.filename,
        content_type: attachment.content_type&.split(";")&.first
      )
    end
  end
end
