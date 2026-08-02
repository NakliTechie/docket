# Outbound sequence email — the v1.2 CRM comms gateway. Goes through the
# same SMTP config as every other mail; without SMTP the delivery job records
# a skipped receipt and the null transport remains the final egress fail-safe.
class CrmMailer < ApplicationMailer
  def sequence_delivery(delivery)
    @body = delivery.payload.fetch("body", "")
    @body_html = SequenceTracking.html_body(delivery)
    @open_url = SequenceTracking.open_url(delivery)
    @unsubscribe_url = SequenceUnsubscribe.url_for(delivery.sequence_enrollment.enrollable)
    @reply_address = SequenceTracking.reply_address(delivery)
    headers["X-Docket-Delivery-ID"] = "sequence-#{delivery.id}"
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    mail_options = { to: delivery.recipient, subject: delivery.payload.fetch("subject"),
                     template_name: "sequence_step" }
    mail_options[:reply_to] = @reply_address if @reply_address
    mail(**mail_options)
  end
end
