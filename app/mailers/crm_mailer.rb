# Outbound sequence email — the v1.2 CRM comms gateway. Goes through the
# same SMTP config as every other mail; with no SMTP configured, delivery
# is :test (silent), so there's no accidental egress.
class CrmMailer < ApplicationMailer
  def sequence_delivery(delivery)
    @body = delivery.payload.fetch("body", "")
    headers["X-Docket-Delivery-ID"] = "sequence-#{delivery.id}"
    mail to: delivery.recipient, subject: delivery.payload.fetch("subject"),
         template_name: "sequence_step"
  end

  def sequence_step(enrollment, step)
    vars = enrollment.interpolation_vars
    @body = step.render_body(vars)
    subject = step.render_subject(vars).presence || enrollment.sequence.name
    mail to: enrollment.recipient_email, subject: subject
  end
end
