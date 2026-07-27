# SSO providers are configured via the `setup` phase so admin settings
# changes apply without a restart. A provider whose plane is not
# configured fails the request (silent fallback to local auth /
# anonymous portal).
OmniAuth.config.logger = Rails.logger
OmniAuth.config.silence_get_warning = true

Rails.application.config.middleware.use OmniAuth::Builder do
  # Every setup lambda runs inside Sso.with_request_tenant: this is middleware,
  # so no tenant is in scope yet and per-tenant SSO settings would otherwise be
  # invisible (the provider then reports "not configured" and SSO fails).
  provider :openid_connect, name: :staff_oidc, setup: lambda { |env|
    next if OmniAuth.config.test_mode
    Sso.with_request_tenant(env) do
      raise "staff OIDC not configured" unless Sso.staff_oidc_enabled?
      env["omniauth.strategy"].options.deep_merge!(Sso.staff_oidc_options)
    end
  }

  provider :openid_connect, name: :customer_oidc, setup: lambda { |env|
    next if OmniAuth.config.test_mode
    Sso.with_request_tenant(env) do
      raise "customer OIDC not configured" unless Sso.customer_oidc_enabled?
      env["omniauth.strategy"].options.deep_merge!(Sso.customer_oidc_options)
    end
  }

  provider :saml, name: :staff_saml, setup: lambda { |env|
    next if OmniAuth.config.test_mode
    Sso.with_request_tenant(env) do
      raise "staff SAML not configured" unless Sso.staff_saml_enabled?
      env["omniauth.strategy"].options.merge!(Sso.staff_saml_options)
    end
  }

  on_failure do |env|
    SsoFailuresController.action(:show).call(env)
  end
end
