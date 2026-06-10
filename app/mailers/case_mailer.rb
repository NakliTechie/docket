# Outbound mail to citizens: submission confirmation and public-reply
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
end
