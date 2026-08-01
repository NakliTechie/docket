require "test_helper"

class CustomFieldsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:admin)
  end

  test "an administrator manages typed definitions without deleting their contract" do
    post custom_fields_path, params: { custom_field_definition: {
      resource_type: "cases", key: "Customer Segment", label: "Customer segment",
      field_type: "single_select", options_text: "Enterprise\nGrowth\n", required: "1",
      active: "1", reportable: "1", position: "3"
    } }
    assert_redirected_to custom_fields_path(resource_type: "cases")
    definition = CustomFieldDefinition.find_by!(key: "customer_segment")
    assert_equal %w[Enterprise Growth], definition.options
    assert definition.required?

    patch custom_field_path(definition), params: { custom_field_definition: {
      resource_type: "work_items", key: "rewritten", label: "Client segment",
      field_type: "single_select", options_text: "Enterprise\nGrowth", active: "0"
    } }
    assert_redirected_to custom_fields_path(resource_type: "cases")
    definition.reload
    assert_equal "customer_segment", definition.key
    assert_equal "cases", definition.resource_type
    refute definition.active?
  end

  test "case and work forms persist typed custom values including multi-select" do
    CustomFieldDefinition.create!(resource_type: "cases", key: "products", label: "Products",
                                  field_type: :multi_select, options: %w[Email SMS WhatsApp])
    CustomFieldDefinition.create!(resource_type: "work_items", key: "environment", label: "Environment",
                                  field_type: :single_select, options: %w[Production Staging])

    post cases_path, params: { case: {
      subject: "Custom intake", contact_id: contacts(:ravi).id,
      custom_fields: { products: %w[Email SMS] }
    } }
    kase = Case.find_by!(subject: "Custom intake")
    assert_equal %w[Email SMS], kase.custom_fields.fetch("products")

    post project_work_items_path(projects(:pep)), params: { work_item: {
      title: "Custom delivery", kind: "task",
      custom_fields: { environment: "Production" }
    } }
    item = WorkItem.find_by!(title: "Custom delivery")
    assert_equal "Production", item.custom_fields.fetch("environment")
  end

  test "a service agent cannot configure custom fields" do
    sign_in_as users(:agent_a)
    post custom_fields_path, params: { custom_field_definition: {
      resource_type: "cases", key: "secret", label: "Secret", field_type: "short_text"
    } }
    assert_response :forbidden
    refute CustomFieldDefinition.exists?(key: "secret")
  end
end
