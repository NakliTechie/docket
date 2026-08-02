require "test_helper"

class SalesforceImportTest < ActiveSupport::TestCase
  def payload
    {
      "Account" => [ { "Id" => "A1", "Name" => "Northwind Salesforce" } ],
      "User" => [ {
        "Id" => "U1", "Name" => "Asha Agent", "Email" => "asha.sf@example.test",
        "IsActive" => true, "Profile" => { "Name" => "Support Agent" }
      } ],
      "Contact" => [ {
        "Id" => "C1", "AccountId" => "A1", "Name" => "Ravi SF",
        "Email" => "ravi.sf@example.test", "Account_Tier__c" => "Gold"
      } ],
      "Case" => [ {
        "Id" => "K1", "ContactId" => "C1", "OwnerId" => "U1",
        "CaseNumber" => "000123", "Subject" => "Imported Salesforce case",
        "Status" => "Working", "Priority" => "High", "Origin" => "Email",
        "Mystery_Field__c" => "visible in dropped report"
      } ]
    }
  end

  test "preview requires explicit role and status mappings" do
    preview = Imports::Salesforce.preview(payload: payload)
    assert_includes preview.dig(:missing_mappings, :roles), "Support Agent"
    assert_includes preview.dig(:missing_mappings, :case_statuses), "Working"
  end

  test "imports account contact user and case with stable source identities" do
    result = Imports::Salesforce.call(
      payload: payload,
      role_map: { "Support Agent" => "customer_service" },
      status_map: { "Working" => "in_progress" }
    )

    assert_equal 1, result.created["organisations"]
    assert_equal 1, result.created["contacts"]
    assert_equal 1, result.created["users"]
    assert_equal 1, result.created["cases"]
    kase = Case.find_by(external_id: "salesforce:K1")
    assert_equal "in_progress", kase.status
    assert_equal "asha.sf@example.test", kase.assignee.email_address
    assert_equal "Northwind Salesforce", kase.contact.organisation.name
    assert_includes result.serialized_unmapped["dropped.Case"], "Mystery_Field__c"
  end

  test "maps governed CRM custom fields without reporting their source columns as dropped" do
    CustomFieldDefinition.create!(resource_type: "contacts", key: "account_tier", label: "Account tier",
                                  field_type: :single_select, options: %w[Gold Silver])
    result = Imports::Salesforce.call(
      payload: payload,
      role_map: { "Support Agent" => "customer_service" },
      status_map: { "Working" => "in_progress" },
      custom_field_maps: { contacts: { account_tier: "Account_Tier__c" } }
    )

    assert_empty result.errors
    assert_equal "Gold", Contact.find_by!(email: "ravi.sf@example.test").custom_fields.fetch("account_tier")
    refute_includes Array(result.serialized_unmapped["dropped.Contact"]), "Account_Tier__c"
  end

  test "source deletions tombstone previously imported records" do
    Imports::Salesforce.call(payload: payload,
                             role_map: { "Support Agent" => "customer_service" },
                             status_map: { "Working" => "in_progress" })
    organisation = Organisation.find_by!(name: "Northwind Salesforce")

    result = Imports::Salesforce.call(payload: {
      "Account" => [ {
        "Id" => "A1", "Name" => "Northwind Salesforce", "IsDeleted" => true,
        "LastModifiedDate" => "2026-01-02T00:00:00Z"
      } ]
    })

    assert_equal 1, result.deleted["organisations"]
    assert Organisation.with_deleted.find(organisation.id).deleted?
  end

  test "feature-disabled Salesforce object arrays are reported as errors" do
    tenants(:primary).update!(entitlements: Features.preset("service_only"))
    result = Imports::Salesforce.call(payload: {
      "Lead" => [ { "Id" => "L1", "Name" => "Hidden lead" } ],
      "Opportunity" => [ { "Id" => "O1", "Name" => "Hidden deal" } ]
    })

    assert_equal 1, result.skipped["leads"]
    assert_equal 1, result.skipped["deals"]
    assert result.errors.any? { |message| message.include?("Lead rows") }
    assert result.errors.any? { |message| message.include?("Opportunity rows") }
    assert_equal "completed_with_errors", ImportRun.find(result.run_id).status
  end
end
