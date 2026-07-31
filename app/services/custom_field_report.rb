class CustomFieldReport
  Row = Data.define(:value, :label, :count)

  attr_reader :definition, :rows, :total

  def initialize(definition:, scope:)
    @definition = definition
    @scope = scope
    @rows = build_rows.freeze
    @total = @scope.count
  end

  def as_json
    {
      definition: Api::V1::Serialize.custom_field_definition(definition),
      total: total,
      rows: rows.map { |row| { value: row.value, label: row.label, count: row.count } }
    }
  end

  def to_csv
    require "csv"
    CSV.generate do |csv|
      csv << %w[resource field_key field_label value count total]
      rows.each do |row|
        csv << [ definition.resource_type, definition.key, csv_safe(definition.label),
                 csv_safe(row.label), row.count, total ]
      end
    end
  end

  private

  def build_rows
    counts = Hash.new(0)
    @scope.select(:id, :custom_fields).find_each do |record|
      raw = record.custom_fields.to_h[definition.key]
      values = definition.field_type_multi_select? ? Array(raw) : [ raw ]
      values = [ nil ] if values.empty?
      values.each { |value| counts[normalized_key(value)] += 1 }
    end
    counts.map do |value, count|
      Row.new(value: value, label: label_for(value), count: count)
    end.sort_by { |row| [ row.value.nil? ? 1 : 0, -row.count, row.label ] }
  end

  def normalized_key(value)
    CustomFields::Type.blank?(value) ? nil : value
  end

  def label_for(value)
    return I18n.t("custom_fields.report.not_set") if value.nil?

    CustomFields::Type.human(definition, value)
  end

  def csv_safe(value)
    value.to_s.match?(/\A[=+\-@\t]/) ? "'#{value}" : value
  end
end
