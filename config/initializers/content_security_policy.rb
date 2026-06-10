# Strict CSP (handoff §8): no inline script, no external origins. The
# importmap <script> is permitted via per-request nonce. The only
# network egress Docket ever performs is server-side (configured LLM
# endpoint + outbound mail), so browser-side connect stays :self.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :none
    policy.script_src  :self
    policy.style_src   :self
    policy.img_src     :self, :data
    policy.font_src    :self
    policy.connect_src :self
    policy.form_action :self
    policy.frame_ancestors :none
    policy.base_uri    :self
    policy.object_src  :none
  end

  config.content_security_policy_nonce_generator = ->(request) {
    request.session.id.to_s.presence || SecureRandom.base64(16)
  }
  config.content_security_policy_nonce_directives = %w[script-src]
end
