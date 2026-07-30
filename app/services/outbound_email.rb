# The production delivery seam. Docket deliberately falls back to Action
# Mailer's test adapter when no SMTP gateway is configured, so "a mail job ran"
# does not mean a customer can receive anything.
module OutboundEmail
  module_function

  def configured?
    ENV["SMTP_ADDRESS"].present?
  end
end
