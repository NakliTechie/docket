module CustomFields
  module Type
    Result = Data.define(:value, :error) do
      def valid? = error.nil?
    end

    module_function

    def coerce(definition, input)
      return Result.new(value: empty_value(definition), error: nil) if blank?(input)

      value = case definition.field_type
      when "short_text" then text(input, maximum: 255)
      when "long_text" then text(input, maximum: 10_000)
      when "integer" then Integer(input.to_s, 10)
      when "decimal" then BigDecimal(input.to_s).to_s("F")
      when "boolean" then boolean(input)
      when "date" then Date.iso8601(input.to_s).iso8601
      when "single_select" then selected(definition, input.to_s)
      when "multi_select" then multi_selected(definition, input)
      else raise ArgumentError, "unknown custom field type"
      end
      Result.new(value: value, error: nil)
    rescue ArgumentError, TypeError => error
      Result.new(value: input, error: error.message)
    end

    def human(definition, value)
      return "—" if blank?(value)
      return I18n.t(value ? "custom_fields.values.yes" : "custom_fields.values.no") if definition.field_type_boolean?
      return Array(value).join(", ") if definition.field_type_multi_select?

      value.to_s
    end

    def blank?(value)
      value.nil? || value == "" || value == []
    end

    def empty_value(definition)
      definition.field_type_multi_select? ? [] : nil
    end

    def text(input, maximum:)
      value = input.to_s.strip
      raise ArgumentError, "is longer than #{maximum} characters" if value.length > maximum

      value
    end

    def boolean(input)
      values = { true => true, false => false, 1 => true, 0 => false,
                 "1" => true, "0" => false, "true" => true, "false" => false }
      values.fetch(input) { raise ArgumentError, "must be true or false" }
    end

    def selected(definition, value)
      raise ArgumentError, "is not an allowed option" unless definition.options.include?(value)

      value
    end

    def multi_selected(definition, input)
      values = Array(input).map(&:to_s).reject(&:blank?).uniq
      raise ArgumentError, "contains an option that is not allowed" unless (values - definition.options).empty?

      values
    end
  end
end
