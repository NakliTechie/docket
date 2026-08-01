module CustomFields
  class ImportMapping
    attr_reader :consumed_sources

    def initialize(resource_type:, mapping:, result:)
      @resource_type = resource_type
      @mapping = mapping.to_h.stringify_keys.transform_values(&:to_s)
      @result = result
      @definitions = CustomFieldDefinition.for_resource(resource_type).index_by(&:key)
      @consumed_sources = @mapping.values
      validate_targets
    end

    def valid? = @unknown_targets.empty?

    def values(source)
      return {} unless source.is_a?(Hash)

      @mapping.each_with_object({}) do |(target, source_key), values|
        next unless source.key?(source_key)

        definition = @definitions[target]
        next unless definition

        raw = normalize_multi_value(definition, source[source_key])
        result = Type.coerce(definition, raw)
        if result.valid?
          values[target] = result.value
        else
          @result.unmapped!("custom_field.#{target}", source[source_key])
        end
      end
    end

    private

    def validate_targets
      @unknown_targets = @mapping.keys - @definitions.keys
      @unknown_targets.each do |target|
        @result.error!("custom field #{target.inspect} is not defined for #{@resource_type}")
      end
    end

    def normalize_multi_value(definition, value)
      return value unless definition.field_type_multi_select? && value.is_a?(String)

      value.split(/[;,]/).map(&:strip).reject(&:blank?)
    end
  end
end
