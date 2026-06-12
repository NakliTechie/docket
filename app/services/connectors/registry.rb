module Connectors
  # The catalogue of available providers. Add a roadmap connector by
  # writing a Provider subclass and registering its key here.
  module Registry
    module_function

    def providers
      { "http_json" => Connectors::HttpJsonProvider }
    end

    def keys
      providers.keys
    end

    def key?(key)
      providers.key?(key.to_s)
    end

    def klass(key)
      providers[key.to_s]
    end

    def descriptor(key)
      klass(key)&.descriptor
    end

    def build(key, connector)
      providers.fetch(key.to_s).new(connector)
    end

    # For the admin "new connector" picker.
    def descriptors
      providers.values.map(&:descriptor)
    end

    # Anthropic tool-use specs for one connector's actions — the agent-facing
    # view of the same Provider::Action structs the admin UI lists. Names are
    # namespaced by connector id so several connectors of the same provider
    # never collide in a single tool set.
    def tool_specs(connector)
      klass(connector.provider)&.actions.to_a.map do |action|
        {
          name: "conn_#{connector.id}__#{action.key}",
          description: action.summary,
          input_schema: action.params || { "type" => "object", "properties" => {} }
        }
      end
    end
  end
end
