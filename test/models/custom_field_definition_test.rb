require "test_helper"

class CustomFieldDefinitionTest < ActiveSupport::TestCase
  test "normalizes keys and validates select options" do
    field = CustomFieldDefinition.new(
      resource_type: "cases", key: "Customer Region", label: "Customer region",
      field_type: :single_select, options: [ " North ", "South", "North" ]
    )

    assert field.save
    assert_equal "customer_region", field.key
    assert_equal [ "North", "South" ], field.options

    field.options = []
    refute field.valid?
  end

  test "keys cannot be changed after data may depend on them" do
    field = create_field
    field.key = "new_key"

    refute field.valid?
    assert field.errors.of_kind?(:key, :immutable)
  end

  test "fields are unique within a resource but reusable across resources" do
    create_field(key: "region", label: "Region")
    duplicate = build_field(key: "region", label: "Other label")
    refute duplicate.valid?

    assert build_field(resource_type: "work_items", key: "region", label: "Region").valid?
  end

  private

  def build_field(**attributes)
    CustomFieldDefinition.new({
      resource_type: "cases", key: "region", label: "Region", field_type: :short_text
    }.merge(attributes))
  end

  def create_field(**attributes)
    build_field(**attributes).tap(&:save!)
  end
end
