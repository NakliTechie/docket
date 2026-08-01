require "test_helper"

# CPGRAMS export — the status + Action-Taken-Report round-trip a department
# uploads back to CPGRAMS after working grievances in Docket.
class CpgramsExportTest < ActiveSupport::TestCase
  test "exports only CPGRAMS-sourced cases, with mapped status and the latest ATR" do
    contact = contacts(:asha)
    kase = Case.create!(subject: "Grievance", contact: contact,
                        external_id: "cpgrams:DOCAF/E/2024/0099999")
    kase.messages.create!(kind: :public_reply, direction: :outbound,
                          body: "Resolved and refunded.", author: users(:agent_a))
    kase.transition_to!(:in_progress)
    kase.transition_to!(:resolved)
    Case.create!(subject: "Not a grievance", contact: contact) # no cpgrams external_id

    payload = Exports::Cpgrams.new.call
    assert payload["generated_at"].present?
    grievances = payload["grievances"]
    assert_equal 1, grievances.size, "a non-CPGRAMS case must not leak into the export"

    grievance = grievances.first
    assert_equal "DOCAF/E/2024/0099999", grievance["registration_number"]
    assert_equal "Disposed of", grievance["status"]
    assert_equal "Resolved and refunded.", grievance["action_taken_report"]
    assert_not_nil grievance["disposed_on"]
    assert_equal kase.tracking_id, grievance["docket_tracking_id"]
  end

  test "a fresh grievance maps to the CPGRAMS Receipt status" do
    Case.create!(subject: "New grievance", contact: contacts(:asha),
                 external_id: "cpgrams:DOCAF/E/2024/0088888")
    grievance = Exports::Cpgrams.new.call["grievances"]
                                .find { |row| row["registration_number"] == "DOCAF/E/2024/0088888" }
    assert_equal "Receipt", grievance["status"]
    assert_nil grievance["action_taken_report"]
  end

  test "the export round-trips an imported grievance's registration number" do
    Imports::Cpgrams.call(payload: {
      "grievances" => [ {
        "registration_number" => "DOCAF/E/2024/0077777", "subject" => "Round trip",
        "grievance_description" => "desc", "status" => "Under Process",
        "complainant" => { "name" => "Sita", "email" => "sita@example.com" }
      } ]
    })
    numbers = Exports::Cpgrams.new.call["grievances"].map { |row| row["registration_number"] }
    assert_includes numbers, "DOCAF/E/2024/0077777"
  end
end
