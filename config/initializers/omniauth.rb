# SSO providers are configured via the `setup` phase so admin settings
# changes apply without a restart. A provider whose plane is not
# configured fails the request (silent fallback to local auth /
# anonymous portal).
OmniAuth.config.logger = Rails.logger
OmniAuth.config.silence_get_warning = true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :openid_connect, name: :staff_oidc, setup: lambda { |env|
    next if OmniAuth.config.test_mode
    raise "staff OIDC not configured" unless Sso.staff_oidc_enabled?
    env["omniauth.strategy"].options.deep_merge!(Sso.staff_oidc_options)
  }

  provider :openid_connect, name: :customer_oidc, setup: lambda { |env|
    next if OmniAuth.config.test_mode
    raise "customer OIDC not configured" unless Sso.customer_oidc_enabled?
    env["omniauth.strategy"].options.deep_merge!(Sso.customer_oidc_options)
  }

  provider :saml, name: :staff_saml, setup: lambda { |env|
    next if OmniAuth.config.test_mode
    raise "staff SAML not configured" unless Sso.staff_saml_enabled?
    env["omniauth.strategy"].options.merge!(Sso.staff_saml_options)
  }

  on_failure do |env|
    SsoFailuresController.action(:show).call(env)
  end
end
