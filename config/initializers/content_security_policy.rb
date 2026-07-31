# Strict CSP (handoff §8): no inline script, no external origins. The
# importmap <script> is permitted via per-request nonce. The only
# browser-side egress is intentionally absent, so connect-src stays :self.
# Server-side egress includes configured LLM, mail, connectors, webhooks, SMS,
# and migration sources; each boundary owns its own transport policy.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :none
    policy.script_src  :self
    policy.style_src   :self
    policy.img_src     :self, :data
    policy.font_src    :self
    policy.connect_src :self
    # The IdP origins must be allowed here: browsers enforce form-action
    # against the redirect target of the POST /auth/* form submission, so
    # 'self' alone blocks every SSO login. Evaluated per request (lambda)
    # so admin settings changes apply without a restart.
    policy.form_action :self, -> { Sso.idp_form_action_origins }
    policy.frame_ancestors :none
    policy.base_uri    :self
    policy.object_src  :none
  end

  # A fresh random nonce per request (Rails memoizes it within the request, so
  # every emitted <script>/<style> shares it and matches the header). Turbo
  # reads the nonce meta tag for its progress-bar stylesheet; allowing that
  # nonce under style-src keeps the policy strict without losing navigation
  # feedback. Not derived from the session id, which would be stable across the
  # session's responses and thus more predictable/reusable (L12).
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
