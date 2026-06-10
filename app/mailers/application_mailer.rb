class ApplicationMailer < ActionMailer::Base
  default from: -> { Setting.get("outbound_email_from", ENV.fetch("DOCKET_MAIL_FROM", "no-reply@docket.local")) }
  layout "mailer"
end
