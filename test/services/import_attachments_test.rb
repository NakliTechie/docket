require "test_helper"

class ImportAttachmentsTest < ActiveSupport::TestCase
  test "Freshdesk ticket attachments retain one resumable blob identity" do
    payload = {
      "contacts" => [ { "id" => 1, "name" => "Ravi", "email" => "attach.ravi@example.test" } ],
      "tickets" => [ {
        "id" => 10, "requester_id" => 1, "subject" => "Attachment history",
        "status" => 2, "priority" => 2, "source" => 1,
        "attachments" => [ {
          "id" => 99, "name" => "history.txt", "content_type" => "text/plain",
          "size" => 7, "data" => Base64.strict_encode64("history")
        } ]
      } ]
    }

    first = Imports::Freshdesk.call(payload: payload)
    second = Imports::Freshdesk.call(payload: payload)
    kase = Case.find_by(external_id: "freshdesk:10")

    assert_equal 1, first.created["attachments"]
    assert_equal 1, second.skipped["attachments"]
    assert_equal 1, kase.files.count
    identity = ImportIdentity.find_by(source: "freshdesk", source_type: "ticket_attachment",
                                      external_id: "99")
    assert_equal kase.files.first.blob, identity.target
  end

  test "unsupported historical attachments are reported and never stored" do
    payload = {
      "contacts" => [ { "id" => 1, "name" => "Ravi", "email" => "bad.attach@example.test" } ],
      "tickets" => [ {
        "id" => 11, "requester_id" => 1, "subject" => "Unsafe attachment",
        "status" => 2, "attachments" => [ {
          "id" => 100, "name" => "program.exe",
          "content_type" => "application/x-msdownload",
          "data" => Base64.strict_encode64("MZ")
        } ]
      } ]
    }

    result = Imports::Freshdesk.call(payload: payload)

    assert_equal 0, Case.find_by(external_id: "freshdesk:11").files.count
    assert_includes result.serialized_unmapped["attachment_content_type"],
                    "application/x-msdownload"
  end
end
