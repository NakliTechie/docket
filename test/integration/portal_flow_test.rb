require "test_helper"

class PortalFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "citizen files a grievance anonymously and receives a tracking id" do
    assert_difference [ "Case.count", "Contact.count", "Message.count" ], 1 do
      assert_enqueued_emails 1 do
        post portal_cases_path, params: { portal_submission: {
          name: "Sita Devi", email: "sita@example.com",
          subject: "Water supply disruption",
          description: "No water for three days."
        } }
      end
    end
    assert_response :created
    kase = Case.order(:id).last
    assert_select "[data-test-id=tracking-id]", text: kase.tracking_id
    assert_equal "web_portal", kase.channel
    assert_equal "sita@example.com", kase.contact.email
    assert_equal "No water for three days.", kase.messages.first.body
    assert_equal "inbound", kase.messages.first.direction
  end

  test "string file params are ignored (no attach-by-reference or 500) (M12)" do
    assert_difference "Case.count", 1 do
      post portal_cases_path, params: { portal_submission: {
        name: "Citizen", email: "filecitizen@example.com",
        subject: "Has bad file param", description: "Body",
        files: [ "some-active-storage-signed-id-or-garbage" ]
      } }
    end
    assert_response :created # rendered confirmation, not a 500
    assert_empty Case.order(:id).last.messages.first.files
  end

  test "submission reuses an existing contact by email" do
    assert_no_difference "Contact.count" do
      post portal_cases_path, params: { portal_submission: {
        name: "A. Rao", email: contacts(:asha).email,
        subject: "Second matter", description: "Details here."
      } }
    end
    assert_equal contacts(:asha), Case.order(:id).last.contact
  end

  test "submission without any contact channel is rejected with inline errors" do
    assert_no_difference "Case.count" do
      post portal_cases_path, params: { portal_submission: {
        name: "Ghost", subject: "No channels", description: "Cannot reach me."
      } }
    end
    assert_response :unprocessable_entity
    assert_select ".form-errors"
  end

  test "tracking requires the matching contact detail" do
    kase = cases(:pension_case)
    post portal_track_lookup_path, params: { tracking_id: kase.tracking_id, contact_email: "wrong@example.com" }
    assert_response :unprocessable_entity
    assert_no_match kase.subject, response.body

    post portal_track_lookup_path, params: { tracking_id: kase.tracking_id, contact_email: contacts(:asha).email }
    assert_response :success
    assert_match kase.subject, response.body
  end

  test "unknown tracking id and wrong contact get the same generic error" do
    post portal_track_lookup_path, params: { tracking_id: "DKT-XXXX-XXXX", contact_email: "a@example.com" }
    missing_body = response.body
    post portal_track_lookup_path, params: { tracking_id: cases(:pension_case).tracking_id, contact_email: "b@example.com" }
    assert_equal missing_body.scan(/class="flash[^"]*"/), response.body.scan(/class="flash[^"]*"/)
  end

  test "status page hides internal notes" do
    kase = cases(:pension_case)
    post portal_track_lookup_path, params: { tracking_id: kase.tracking_id, contact_email: contacts(:asha).email }
    assert_response :success
    assert_no_match messages(:note_on_pension).body, response.body
  end

  test "citizen reply lands on the case and reopens the conversation" do
    kase = cases(:waiting_case)
    assert_difference "kase.messages.count" do
      post portal_track_reply_path, params: {
        tracking_id: kase.tracking_id, contact_email: contacts(:asha).email,
        body: "Here is the extra information."
      }
    end
    assert_response :success
    assert_equal "in_progress", kase.reload.status
    message = kase.messages.order(:id).last
    assert_equal "inbound", message.direction
    assert_equal contacts(:asha), message.author
  end

  test "closed cases do not accept replies" do
    kase = cases(:resolved_case)
    kase.transition_to!(:closed)
    assert_no_difference "Message.count" do
      post portal_track_reply_path, params: {
        tracking_id: kase.tracking_id, contact_phone: contacts(:ravi).phone,
        body: "One more thing."
      }
    end
    assert_response :unprocessable_entity
  end

  test "oversized or wrong-type uploads are rejected" do
    bad_file = Rack::Test::UploadedFile.new(
      StringIO.new("MZ fake executable"), "application/x-msdownload", original_filename: "evil.exe"
    )
    assert_no_difference "Case.count" do
      post portal_cases_path, params: { portal_submission: {
        name: "Up Loader", email: "uploader@example.com",
        subject: "With file", description: "Attached.", files: [ bad_file ]
      } }
    end
    assert_response :unprocessable_entity
  end

  test "portal is reachable without authentication and in hindi" do
    get portal_root_path
    assert_response :success
    post locale_path(locale: "hi")
    get portal_root_path
    assert_match I18n.t("portal.cases.new.title", locale: :hi), response.body
  end
end
