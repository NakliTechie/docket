module Imports
  # Reports every non-empty source field an adapter did not consume. Import
  # contracts are deliberately explicit: a migration may drop data only when
  # the operator can see the exact field name in the preview/result.
  class FieldContract
    def initialize(result, source_type, consumed)
      @result = result
      @source_type = source_type
      @consumed = consumed.map(&:to_s).to_set
    end

    def inspect!(row)
      row.each do |field, value|
        next if @consumed.include?(field.to_s) || blank_source_value?(value)

        @result.drop!(@source_type, field)
      end
    end

    private

    def blank_source_value?(value)
      value.nil? || value == "" || value == [] || value == {}
    end
  end
end
