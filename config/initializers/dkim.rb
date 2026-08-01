require Rails.root.join("lib/docket/dkim_signer")

if (docket_dkim_signer = Docket::DkimSigner.from_environment)
  ActionMailer::Base.register_interceptor(docket_dkim_signer)
end
