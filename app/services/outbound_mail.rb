module OutboundMail
  module_function

  def available?
    Rails.application.config.x.outbound_mail_available == true
  end
end
