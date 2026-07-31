module HasCustomFields
  extend ActiveSupport::Concern

  included do
    class_attribute :custom_field_resource_type, instance_accessor: false
    validate :custom_field_values_are_valid
  end

  class_methods do
    def has_custom_fields_for(resource_type)
      self.custom_field_resource_type = resource_type.to_s
    end
  end

  def custom_fields=(values)
    super((values || {}).to_h.stringify_keys)
    @custom_field_definitions = nil
  end

  def assign_custom_fields(values = nil, replace: false, **attributes)
    incoming = (values || attributes).to_h.stringify_keys
    self.custom_fields = replace ? incoming : custom_fields.to_h.merge(incoming)
  end

  def custom_field_definitions(active: false)
    scope = CustomFieldDefinition.for_resource(self.class.custom_field_resource_type).ordered
    active ? scope.active : scope
  end

  private

  def custom_field_values_are_valid
    definitions = custom_field_definitions.index_by(&:key)
    values = custom_fields.to_h.stringify_keys
    unknown = values.keys - definitions.keys
    errors.add(:custom_fields, :unknown, keys: unknown.join(", ")) if unknown.any?

    normalized = {}
    definitions.each_value do |definition|
      raw = values[definition.key]
      if definition.active? && definition.required? && CustomFields::Type.blank?(raw)
        errors.add(:custom_fields, :required, label: definition.label)
        next
      end
      next unless values.key?(definition.key)

      result = CustomFields::Type.coerce(definition, raw)
      if result.valid?
        normalized[definition.key] = result.value
      else
        errors.add(:custom_fields, :invalid, label: definition.label, reason: result.error)
      end
    end
    self[:custom_fields] = normalized unless errors[:custom_fields].any?
  end
end
