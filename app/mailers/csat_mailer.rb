class CsatMailer < ApplicationMailer
  def invitation(survey)
    @survey = survey
    @kase = survey.case
    @token = survey.signed_id(purpose: :csat, expires_in: 90.days)
    mail to: survey.contact.email,
         subject: t("csat_mailer.invitation.subject", tracking_id: @kase.tracking_id)
  end
end
