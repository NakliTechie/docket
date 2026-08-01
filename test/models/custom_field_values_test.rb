require "test_helper"

class CustomFieldValuesTest < ActiveSupport::TestCase
  test "coerces every supported type on cases" do
    definitions = [
      field("summary", :short_text), field("detail", :long_text),
      field("seats", :integer), field("score", :decimal),
      field("renewal", :date), field("vip", :boolean),
      field("region", :single_select, options: %w[North South]),
      field("products", :multi_select, options: %w[Email SMS WhatsApp])
    ]
    kase = cases(:pension_case)
    kase.assign_custom_fields(
      summary: " Enterprise ", detail: "Needs migration", seats: "42", score: "12.50",
      renewal: "2026-12-31", vip: "true", region: "North",
      products: [ "Email", "SMS", "SMS" ]
    )

    assert kase.save
    assert_equal "Enterprise", kase.custom_fields.fetch("summary")
    assert_equal 42, kase.custom_fields.fetch("seats")
    assert_equal "12.5", kase.custom_fields.fetch("score")
    assert_equal "2026-12-31", kase.custom_fields.fetch("renewal")
    assert_equal true, kase.custom_fields.fetch("vip")
    assert_equal %w[Email SMS], kase.custom_fields.fetch("products")
    assert_equal definitions.map(&:key).sort, kase.custom_fields.keys.sort
  end

  test "rejects unknown keys and invalid typed values" do
    field("seats", :integer)
    field("region", :single_select, options: %w[North South])
    kase = cases(:pension_case)
    kase.custom_fields = { seats: "many", region: "West", surprise: "value" }

    refute kase.valid?
    assert_operator kase.errors[:custom_fields].size, :>=, 3
  end

  test "active required fields apply to both pillars" do
    field("environment", :short_text, resource_type: "work_items", required: true)
    item = work_items(:pep_one)
    refute item.valid?

    item.assign_custom_fields(environment: "Production")
    assert item.save
  end

  test "deactivated fields remain readable without blocking unrelated edits" do
    definition = field("legacy_tier", :short_text)
    kase = cases(:pension_case)
    kase.assign_custom_fields(legacy_tier: "Gold")
    kase.save!
    definition.update!(active: false, required: true)

    assert kase.update(subject: "Edited after deactivation")
    assert_equal "Gold", kase.reload.custom_fields.fetch("legacy_tier")
  end

  private

  def field(key, field_type, resource_type: "cases", **attributes)
    CustomFieldDefinition.create!({
      resource_type: resource_type, key: key, label: key.humanize, field_type: field_type
    }.merge(attributes))
  end
end
