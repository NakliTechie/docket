require Rails.root.join("lib/docket/null_mail_delivery")

ActionMailer::Base.add_delivery_method :docket_null, Docket::NullMailDelivery
