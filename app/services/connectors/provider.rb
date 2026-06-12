module Connectors
  # Base class for a provider. A subclass declares a Descriptor (how the
  # admin UI presents it), implements #fetch to pull records inbound, and —
  # to be usable by an AI agent as an effector — declares .actions and
  # implements #invoke to take outbound actions.
  class Provider
    # key            — registry id, also the DB `provider` value
    # name           — human label in the admin picker
    # category       — grouping in the picker
    # auth           — :none | :api_key (what the credential form asks for)
    # config_fields  — provider config keys the admin fills in
    Descriptor = Struct.new(:key, :name, :category, :auth, :config_fields, keyword_init: true)

    # An agent-callable action. The SAME struct backs the admin "what can
    # this connector do" list and the LLM tool spec (see Registry.tool_specs).
    #   key     — stable action id (also the audit/invocation verb)
    #   name    — human label
    #   summary — natural-language description handed to the model
    #   params  — JSON Schema (Hash) for the action's arguments
    #   effect  — :read | :write | :irreversible → drives the approval gate
    Action = Struct.new(:key, :name, :summary, :params, :effect, keyword_init: true) do
      EFFECTS = %i[read write irreversible].freeze

      # Reads run unattended; anything that mutates the outside world needs a
      # human-of-record unless the connector explicitly auto-approves it.
      def requires_approval? = effect != :read
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
  end
end
