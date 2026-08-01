require "test_helper"

# CPGRAMS grievance import — the government-vertical route in. Works from an
# export file, defaults dry, reports unknown values rather than guessing.
class CpgramsImportTest < ActiveSupport::TestCase
  def grievance_export(overrides = {})
    {
      "grievances" => [ {
        "registration_number" => "DOCAF/E/2024/0012345",
        "subject" => "Pension not credited",
        "grievance_description" => "My pension for May has not been credited to my account.",
        "status" => "Under Process",
        "priority" => "High",
        "ministry" => "Department of Financial Services",
        "received_on" => "2024-05-01T10:00:00Z",
        "complainant" => { "name" => "Ramesh Kumar", "email" => "ramesh@example.com",
                           "mobile" => "9876543210", "state" => "Maharashtra", "district" => "Pune" },
        "remarks" => [ { "id" => "r1", "by" => "Disbursing Officer",
                         "text" => "Forwarded to the pension disbursing bank.",
                         "on" => "2024-05-02T10:00:00Z" } ]
      }.merge(overrides) ]
    }
  end

  test "a grievance becomes a case with its complainant and ATR remark" do
    result = Imports::Cpgrams.call(payload: grievance_export)

    assert_equal 1, result.created["cases"]
    kase = Case.find_by(external_id: "cpgrams:DOCAF/E/2024/0012345")
    assert_equal "Pension not credited", kase.subject
    assert_equal "in_progress", kase.status
    assert_equal "high", kase.priority
    assert_equal "web_portal", kase.channel
    assert_equal "ramesh@example.com", kase.contact.email
    assert_equal "9876543210", kase.contact.phone
    assert_equal 1, kase.messages.count
    remark = kase.messages.first
    assert remark.kind_public_reply?
    assert remark.direction_outbound?
    assert_equal "Disbursing Officer", remark.source_author_name
  end

  test "the CPGRAMS status vocabulary maps to Docket statuses" do
    {
      "Receipt" => "new", "Under Process" => "in_progress",
      "Awaiting Citizen" => "waiting_on_customer", "Disposed of" => "resolved", "Closed" => "closed"
    }.each_with_index do |(cpgrams, docket), index|
      reg = "DOCAF/E/2024/010#{index}"
      Imports::Cpgrams.call(payload: grievance_export("registration_number" => reg, "status" => cpgrams))
      assert_equal docket, Case.find_by(external_id: "cpgrams:#{reg}").status, "#{cpgrams} → #{docket}"
    end
  end

  test "a disposed grievance restores its disposal time" do
    Imports::Cpgrams.call(payload: grievance_export("status" => "Disposed of",
                                                    "disposed_on" => "2024-05-10T09:00:00Z"))
    kase = Case.find_by(external_id: "cpgrams:DOCAF/E/2024/0012345")
    assert_equal "resolved", kase.status
    assert_not_nil kase.resolved_at
  end

  test "a dry run reports without writing" do
    assert_no_difference "Case.count" do
      Imports::Cpgrams.call(payload: grievance_export, dry_run: true)
    end
  end

  test "re-running is idempotent on the registration number" do
    Imports::Cpgrams.call(payload: grievance_export)
    assert_difference "Case.count", 0 do
      Imports::Cpgrams.call(payload: grievance_export)
    end
  end

  test "an unknown status is reported, never guessed" do
    result = Imports::Cpgrams.call(payload: grievance_export("status" => "On the Moon"))
    assert_includes result.to_h[:unmapped]["status"], "On the Moon"
    assert_nil Case.find_by(external_id: "cpgrams:DOCAF/E/2024/0012345")
  end

  test "state and district are reported as unmapped dimensions, not guessed onto the record" do
    result = Imports::Cpgrams.call(payload: grievance_export)
    assert result.serialized_unmapped.key?("state")
    assert result.serialized_unmapped.key?("district")
  end

  test "an unmapped ministry is reported and falls back to the default queue" do
    result = Imports::Cpgrams.call(payload: grievance_export, default_queue: CaseQueue.first)
    kase = Case.find_by(external_id: "cpgrams:DOCAF/E/2024/0012345")
    assert_equal CaseQueue.first.id, kase.queue_id
    assert result.serialized_unmapped.key?("ministry")
  end
end
