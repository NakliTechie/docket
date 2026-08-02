require "test_helper"

class CustomFieldReportsTest < ActionDispatch::IntegrationTest
  setup do
    @field = CustomFieldDefinition.create!(resource_type: "cases", key: "region", label: "Region",
                                           field_type: :single_select,
                                           options: %w[North South], reportable: true)
    cases(:pension_case).assign_custom_fields(region: "North")
    cases(:pension_case).save!
  end

  test "staff can inspect a reportable field" do
    sign_in_as users(:agent_a)
    get custom_field_report_path, params: { resource_type: "cases", field: "region" }
    assert_response :success
    assert_match "North", response.body
    assert_match "Not set", response.body
  end

  test "export permission holders can download a reportable field" do
    sign_in_as users(:admin)
    get custom_field_report_path(format: :csv), params: { resource_type: "cases", field: "region" }
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "resource,field_key,field_label,value,count,total", response.body
  end

  test "staff without export permission cannot download a reportable field" do
    sign_in_as users(:agent_a)
    get custom_field_report_path(format: :csv), params: { resource_type: "cases", field: "region" }
    assert_response :forbidden
  end

  test "non-reportable fields cannot be queried" do
    @field.update!(reportable: false)
    sign_in_as users(:admin)
    get custom_field_report_path, params: { resource_type: "cases", field: "region" }
    assert_response :not_found
  end

  test "CRM field reports use the matching record scope" do
    definition = CustomFieldDefinition.create!(resource_type: "contacts", key: "account_tier",
                                               label: "Account tier", field_type: :short_text,
                                               reportable: true)
    contacts(:asha).assign_custom_fields(account_tier: "Gold")
    contacts(:asha).save!
    sign_in_as users(:admin)

    get custom_field_report_path, params: { resource_type: "contacts", field: definition.key }
    assert_response :success
    assert_match "Gold", response.body
  end
end
