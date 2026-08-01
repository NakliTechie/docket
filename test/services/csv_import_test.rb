require "test_helper"

class CsvImportTest < ActiveSupport::TestCase
  def csv
    <<~CSV
      Source ID,Full Name,Email,Legacy Segment
      C-100,Ravi Kumar,ravi.csv@example.test,Gold
    CSV
  end

  def mapping
    { "name" => "Full Name", "email" => "Email" }
  end

  test "preview reports dropped columns and apply uses a durable identity" do
    preview = Imports::Csv.preview(payload: csv, entity: "contacts",
                                   identity_column: "Source ID", mapping: mapping)
    assert_empty preview[:errors]
    assert_includes preview[:unmapped_columns], "Legacy Segment"

    result = Imports::Csv.call(payload: csv, entity: "contacts",
                               identity_column: "Source ID", mapping: mapping)
    assert_equal 1, result.created["contacts"]
    contact = Contact.find_by(email: "ravi.csv@example.test")
    assert_equal contact, ImportIdentity.find_by(source: "csv", external_id: "C-100").target
    assert_includes result.serialized_unmapped["dropped.csv.contacts"], "Legacy Segment"
  end

  test "an enum value without an explicit mapping fails preview" do
    payload = "ID,Name,Email,Role\nU-1,Asha,asha.csv@example.test,Support Hero\n"
    preview = Imports::Csv.preview(
      payload: payload, entity: "users", identity_column: "ID",
      mapping: { name: "Name", email_address: "Email", role: "Role" }
    )

    assert_equal [ "Support Hero" ], preview.dig(:unmapped_values, "role")
  end

  test "dry run validates the same contract without retaining a contact" do
    result = Imports::Csv.call(payload: csv, entity: "contacts",
                               identity_column: "Source ID", mapping: mapping, dry_run: true)
    assert_equal 1, result.created["contacts"]
    assert_not Contact.exists?(email: "ravi.csv@example.test")
  end

  test "case contracts map typed custom fields and reject undefined targets in preview" do
    CustomFieldDefinition.create!(resource_type: "cases", key: "segment", label: "Segment",
                                  field_type: :single_select, options: %w[Gold Silver])
    payload = "ID,Subject,Contact,Status,Legacy Segment\nT-1,Imported case,CIF447192,new,Gold\n"
    contract = {
      subject: "Subject", contact_external_id: "Contact", status: "Status",
      "custom_fields.segment" => "Legacy Segment"
    }
    preview = Imports::Csv.preview(payload: payload, entity: "cases", identity_column: "ID",
                                   mapping: contract)
    assert_empty preview[:errors]

    result = Imports::Csv.call(payload: payload, entity: "cases", identity_column: "ID",
                               mapping: contract)
    assert_empty result.errors
    assert_equal "Gold", Case.find_by!(external_id: "csv:T-1").custom_fields.fetch("segment")

    invalid = Imports::Csv.preview(payload: payload, entity: "cases", identity_column: "ID",
                                   mapping: contract.merge("custom_fields.missing" => "Legacy Segment"))
    assert_includes invalid[:errors], 'custom field "missing" is not defined for cases'
  end
end
