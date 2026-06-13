module Connectors
  # Base class for a provider. A subclass declares a Descriptor (how the
  # admin UI presents it), implements #fetch to pull records inbound, and —
  # to be usable by an AI agent as an effector — declares .actions and
  # implements #invoke to take outbound actions.
  class Provider
    # key              — registry id, also the DB `provider` value
    # name             — human label in the admin picker
    # category         — grouping in the picker
    # auth             — :none | :api_key (legacy shorthand; see credential_fields)
    # config_fields    — non-secret provider config keys the admin fills in
    # credential_fields — secret field names stored in the vault (e.g.
    #                    %w[key_id key_secret], %w[webhook_url]). Defaults to
    #                    %w[api_key] when auth is :api_key.
    # syncs            — does the provider pull records inbound? Default true.
    #                    Effector-only providers (notify / pay) set syncs: false,
    #                    which drops the field-mapping requirement.
    # required_credential_fields — secrets that MUST be present before the
    #                    connector can go live. Defaults to all secret_fields;
    #                    a provider with optional auth declares [].
    Descriptor = Struct.new(:key, :name, :category, :auth, :config_fields, :credential_fields,
                            :syncs, :required_credential_fields, keyword_init: true) do
      def secret_fields
        return credential_fields if credential_fields.present?
        auth == :api_key ? %w[api_key] : []
      end

      def syncs? = syncs != false

      def required_secret_fields
        required_credential_fields.nil? ? secret_fields : required_credential_fields
      end
    end

    # An agent-callable action. The SAME struct backs the admin "what can
    # this connector do" list and the LLM tool spec (see Registry.tool_specs).
    #   key            — stable action id (also the audit/invocation verb)
    #   name           — human label
    #   summary        — natural-language description handed to the model
    #   params         — JSON Schema (Hash) for the action's arguments
    #   effect         — :read | :write | :irreversible (technical descriptor)
    #   decision_class — accountability tier (Indian admin-law boundary):
    #     :autonomous — mechanical, rights-neutral → runs unattended
    #     :confirm    — AI prepares, a human confirms before it takes effect
    #     :of_record  — discretionary AND adverse: a human is of record, must
    #                   give a reasoned order, and the decision is contestable;
    #                   never auto-approvable.
    #   When unset, decision_class defaults from effect.
    Action = Struct.new(:key, :name, :summary, :params, :effect, :decision_class, keyword_init: true) do
      EFFECTS = %i[read write irreversible].freeze
      DECISION_CLASSES = %i[autonomous confirm of_record].freeze
      EFFECT_DEFAULT = { read: :autonomous, write: :confirm, irreversible: :of_record }.freeze

      def effective_decision_class
        decision_class || EFFECT_DEFAULT.fetch(effect, :confirm)
      end

      # Reads (autonomous) run unattended; confirm/of_record need a human.
      def requires_approval? = effective_decision_class != :autonomous

      # A decision of record must have a human + a reasoned order; the
      # connector's auto-approve list can never bypass it.
      def of_record? = effective_decision_class == :of_record
    end

    attr_reader :connector

    def initialize(connector)
      @connector = connector
    end

    def self.descriptor
      raise NotImplementedError, "#{name} must define .descriptor"
    end

    # Catalogue of agent-callable actions. Default: none (a pure sync provider).
    def self.actions = []

    def self.action(key)
      actions.find { |a| a.key == key.to_s }
    end

    # → Array of raw record Hashes. Raise Connectors::Error on any failure.
    def fetch
      raise NotImplementedError, "#{self.class.name} must implement #fetch"
    end

    # Execute one action. `args` is the validated argument Hash; `context`
    # carries the invocation (who/on-behalf-of). Returns a plain Hash
    # *observation* the agent reasons on — NOT a row count. Raise
    # Connectors::Error on failure.
    def invoke(action_key, args, context = {})
      raise NotImplementedError, "#{self.class.name} cannot #{action_key}"
    end

    # --- Inbound omnichannel (PG2) --------------------------------------------
    # Does this provider turn inbound webhook payloads into cases (vs. only
    # acting as an outbound effector / pull-sync)? Messaging providers override.
    def self.ingests? = false

    # Authenticate an inbound webhook request. Default: the X-Docket-Signature
    # HMAC over the connector's per-endpoint webhook_secret (the sync-ping
    # scheme). Messaging providers override with their platform's scheme.
    # Fail-closed: a blank/absent signature must not pass.
    def inbound_authentic?(request)
      provided = request.headers["X-Docket-Signature"].to_s
      return false if provided.blank?
      expected = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", connector.webhook_secret.to_s, request.raw_post)}"
      ActiveSupport::SecurityUtils.secure_compare(provided, expected)
    end

    # Normalize a webhook payload into zero or more inbound messages. Each:
    #   { sender: { name:, phone:, external_id: }, external_thread_id:,
    #     body:, channel:, external_message_id: }
    # Non-message events (delivery receipts, edits) → []. Default: not inbound.
    def ingest(_payload) = []

    # Some platforms (Meta/WhatsApp) verify a webhook URL with a GET handshake.
    # → the challenge string to echo, or nil to reject. Default: no handshake.
    def verification_challenge(_params) = nil
  end
end
