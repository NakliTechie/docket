# Outbound mail to customers: submission confirmation and public-reply
# notifications. Subjects carry the tracking ID so email replies thread
# back onto the case (CasesMailbox). Localised to the contact's
# preferred language.
class CaseMailer < ApplicationMailer
  def confirmation(kase)
    @case = kase
    with_contact_locale(kase.contact) do
      mail to: kase.contact.email,
           subject: t("case_mailer.confirmation.subject",
                      tracking_id: kase.tracking_id, subject: kase.subject)
    end
  end

  def public_reply(message)
    @message = message
    @case = message.case
    message.files.each do |file|
      attachments[file.filename.to_s] = { mime_type: file.content_type, content: file.download }
    end
    apply_thread_headers(@case)
    with_contact_locale(@case.contact) do
      mail to: @case.contact.email,
           subject: t("case_mailer.public_reply.subject",
                      tracking_id: @case.tracking_id, subject: @case.subject)
    end
  end

  private

  def with_contact_locale(contact, &block)
    I18n.with_locale(contact.preferred_language.presence || I18n.default_locale, &block)
  end

  def apply_thread_headers(kase)
    message_ids = kase.messages.with_deleted.direction_inbound.where.not(email_message_id: nil)
                      .order(created_at: :desc, id: :desc).limit(20).pluck(:email_message_id)
                      .filter_map { |value| normalized_message_id(value) }.reverse
    return if message_ids.empty?

    headers["In-Reply-To"] = message_ids.last
    headers["References"] = message_ids.join(" ")
  end

  def normalized_message_id(value)
    id = value.to_s.strip.delete_prefix("<").delete_suffix(">")
    "<#{id}>" if id.match?(/\A[^\s<>@]+@[^\s<>]+\z/)
  end
end
