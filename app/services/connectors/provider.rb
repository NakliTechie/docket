module Connectors
  # Base class for a provider. A subclass declares a Descriptor (how the
  # admin UI presents it) and implements #fetch, returning an array of raw
  # external record hashes. Auth, config and field mapping live on the
  # connector; the provider just reads them.
  class Provider
    # key            — registry id, also the DB `provider` value
    # name           — human label in the admin picker
    # category       — grouping in the picker
    # auth           — :none | :api_key (what the credential form asks for)
    # config_fields  — provider config keys the admin fills in
    Descriptor = Struct.new(:key, :name, :category, :auth, :config_fields, keyword_init: true)

    attr_reader :connector

    def initialize(connector)
      @connector = connector
    end

    def self.descriptor
      raise NotImplementedError, "#{name} must define .descriptor"
    end

    # → Array of raw record Hashes. Raise Connectors::Error on any failure.
    def fetch
      raise NotImplementedError, "#{self.class.name} must implement #fetch"
    end
  end
end
