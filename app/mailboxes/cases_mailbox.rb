# Inbound email intake (handoff §3): a tracking ID in the subject
# threads the mail onto its case — but only when the sender matches the
# case contact (anti-spoofing); anything else opens a new case.
# Attachments ride Active Storage under the same allowlist as every
# other upload surface.
class CasesMailbox < ApplicationMailbox
  TRACKING_ID_PATTERN = /DKT-[A-Z2-9]{4}-[A-Z2-9]{4}/

  before_processing :ensure_sender

  def process
    if existing_case && sender_matches?(existing_case)
      thread_onto(existing_case)
    else
      open_new_case
    end
  end

  private

  def ensure_sender
    bounced! if sender_email.blank?
  end

  def sender_email
    @sender_email ||= mail.from&.first.to_s.strip.downcase.presence
  end

  def sender_name
    mail[:from]&.display_names&.first.presence || sender_email.to_s.split("@").first
  end

  def existing_case
    return @existing_case if defined?(@existing_case)
    tracking_id = mail.subject.to_s[TRACKING_ID_PATTERN]
    @existing_case = tracking_id && Case.find_by(tracking_id: tracking_id)
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
    part.decoded.to_s.scrub
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
