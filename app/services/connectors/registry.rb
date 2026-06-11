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
  end
end
