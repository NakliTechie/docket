# The single LLM abstraction (handoff §4). Speaks the OpenAI-compatible
# chat-completions API. Two real configs:
#   in_deployment — operator-owned endpoint (Ollama/vLLM), the default;
#   byok          — external provider, requires the explicit admin
#                   toggle carrying the data-egress warning.
# `fake` backs demos/tests; `off` (or missing config) disables the
# entire AI layer — Docket stays fully usable without it.
module Llm
  class Error < StandardError; end

  PROVIDERS = %w[off in_deployment byok fake].freeze

  def self.provider
    value = Setting.get("llm_provider", "off").to_s
    PROVIDERS.include?(value) ? value : "off"
  end

  def self.enabled?
    client.present?
  end

  def self.client
    case provider
    when "fake"
      FakeClient.new
    when "in_deployment"
      endpoint = Setting.get("llm_endpoint_url").presence
      endpoint && HttpClient.new(endpoint: endpoint, api_key: Setting.get("llm_api_key").presence,
                                 model: Setting.get("llm_model", "llama3"))
    when "byok"
      # BYOK only functions behind the explicit egress acknowledgement.
      return nil unless Setting.get("llm_byok_enabled") == true
      endpoint = Setting.get("llm_endpoint_url").presence
      key = Setting.get("llm_api_key").presence
      endpoint && key && HttpClient.new(endpoint: endpoint, api_key: key,
                                        model: Setting.get("llm_model", "gpt-4o-mini"))
    end
  end
end
