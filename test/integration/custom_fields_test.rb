require "test_helper"

class CustomFieldsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:client_admin)
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

  test "an administrator configures and records CRM custom fields" do
    %w[contacts leads deals].each do |resource_type|
      post custom_fields_path, params: { custom_field_definition: {
        resource_type: resource_type, key: "account_tier", label: "Account tier",
        field_type: "single_select", options_text: "Gold\nSilver", active: "1", reportable: "1"
      } }
      assert_redirected_to custom_fields_path(resource_type: resource_type)
    end

    patch contact_path(contacts(:asha)), params: { contact: { custom_fields: { account_tier: "Gold" } } }
    assert_redirected_to contact_path(contacts(:asha))
    assert_equal "Gold", contacts(:asha).reload.custom_fields.fetch("account_tier")

    post leads_path, params: { lead: {
      name: "Governed lead", email: "governed-lead@example.test",
      custom_fields: { account_tier: "Silver" }
    } }
    lead = Lead.find_by!(email: "governed-lead@example.test")
    assert_equal "Silver", lead.custom_fields.fetch("account_tier")

    post deals_path, params: { deal: {
      name: "Governed deal", pipeline_id: pipelines(:sales).id,
      custom_fields: { account_tier: "Gold" }
    } }
    deal = Deal.find_by!(name: "Governed deal")
    assert_equal "Gold", deal.custom_fields.fetch("account_tier")
  end

  test "support supervisors cannot manage CRM field definitions" do
    sign_in_as users(:customer_service_supervisor)
    post custom_fields_path, params: { custom_field_definition: {
      resource_type: "contacts", key: "private_tier", label: "Private tier", field_type: "short_text"
    } }
    assert_response :forbidden
    refute CustomFieldDefinition.exists?(resource_type: "contacts", key: "private_tier")
  end
end
