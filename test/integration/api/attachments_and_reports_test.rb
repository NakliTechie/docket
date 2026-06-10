require "test_helper"

module Api
  class AttachmentsAndReportsTest < ActionDispatch::IntegrationTest
    setup do
      @admin_token = api_token_for(users(:admin))
    end

    PNG_BYTES = "\x89PNG\r\n\x1a\nfakepayload".b.freeze

    test "message accepts base64 attachments and serves a download url" do
      post "/api/v1/cases/#{cases(:pension_case).id}/messages", params: {
        message: {
          body: "With evidence attached",
          kind: "public_reply",
          attachments: [ { filename: "proof.png", content_type: "image/png",
                           data: Base64.strict_encode64(PNG_BYTES) } ]
        }
      }, headers: auth_header(@admin_token), as: :json
      assert_response :created

      attachment = response.parsed_body["data"]["attachments"].first
      assert_equal "proof.png", attachment["filename"]
      assert attachment["url"].present?

      get attachment["url"], headers: auth_header(@admin_token)
      assert_response :redirect
    end

    test "message accepts multipart file uploads" do
      file = Rack::Test::UploadedFile.new(StringIO.new(PNG_BYTES), "image/png", original_filename: "photo.png")
      post "/api/v1/cases/#{cases(:pension_case).id}/messages", params: {
        message: { body: "Multipart upload", kind: "internal_note", files: [ file ] }
      }, headers: auth_header(@admin_token)
      assert_response :created
      assert_equal "photo.png", response.parsed_body["data"]["attachments"].first["filename"]
    end

    test "disallowed attachment types are rejected with validation errors" do
      assert_no_difference "Message.count" do
        post "/api/v1/cases/#{cases(:pension_case).id}/messages", params: {
          message: {
            body: "Nope",
            attachments: [ { filename: "run.exe", content_type: "application/x-msdownload",
                             data: Base64.strict_encode64("MZ fake") } ]
          }
        }, headers: auth_header(@admin_token), as: :json
      end
      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body["error"]
    end

    test "garbage base64 is rejected cleanly" do
      post "/api/v1/cases/#{cases(:pension_case).id}/messages", params: {
        message: { body: "Nope", attachments: [ { filename: "x.png", content_type: "image/png", data: "@@not-base64@@" } ] }
      }, headers: auth_header(@admin_token), as: :json
      assert_response :unprocessable_entity
      assert_equal "invalid_attachment", response.parsed_body["error"]
    end

    test "oversized base64 is rejected before decoding" do
      post "/api/v1/cases/#{cases(:pension_case).id}/messages", params: {
        message: { body: "Nope", attachments: [ { filename: "big.png", content_type: "image/png",
                                                  data: "A" * (Api::V1::BaseController::MAX_ENCODED_ATTACHMENT_BYTES + 100) } ] }
      }, headers: auth_header(@admin_token), as: :json
      assert_response :unprocessable_entity
      assert_equal "invalid_attachment", response.parsed_body["error"]
    end

    test "case create with attachments rolls back wholly on rejection" do
      assert_no_difference [ "Case.count", "Message.count" ] do
        post "/api/v1/cases", params: {
          case: {
            subject: "With bad file", contact_id: contacts(:asha).id,
            message_body: "see attachment",
            attachments: [ { filename: "run.exe", content_type: "application/x-msdownload",
                             data: Base64.strict_encode64("MZ") } ]
          }
        }, headers: auth_header(@admin_token), as: :json
      end
      assert_response :unprocessable_entity
    end

    test "case create attaches files to the initial message" do
      post "/api/v1/cases", params: {
        case: {
          subject: "With good file", contact_id: contacts(:asha).id,
          message_body: "photo attached",
          attachments: [ { filename: "site.png", content_type: "image/png",
                           data: Base64.strict_encode64(PNG_BYTES) } ]
        }
      }, headers: auth_header(@admin_token), as: :json
      assert_response :created
      message = response.parsed_body["data"]["messages"].first
      assert_equal "site.png", message["attachments"].first["filename"]
    end

    test "on-behalf-of service account can attach citizen evidence" do
      token = service_token_for(%w[cases:write contacts:write])
      post "/api/v1/cases/#{cases(:waiting_case).id}/messages", params: {
        on_behalf_of: contacts(:ravi).external_id,
        message: {
          body: "Uploaded from the mobile app",
          attachments: [ { filename: "receipt.pdf", content_type: "application/pdf",
                           data: Base64.strict_encode64("%PDF-1.4 fake") } ]
        }
      }, headers: auth_header(token), as: :json
      assert_response :created
      assert_equal "inbound", response.parsed_body["data"]["direction"]
      assert_equal "receipt.pdf", response.parsed_body["data"]["attachments"].first["filename"]
    end

    test "activity report endpoint returns full aggregates" do
      Current.set(actor: users(:agent_a)) do
        Contact.create!(name: "Report Subject", email: "report@example.com")
      end
      kase = Case.create!(subject: "Report case", contact: contacts(:asha))
      kase.transition_to!(:triaged)
      kase.transition_to!(:in_progress)
      kase.transition_to!(:resolved)

      get "/api/v1/reports/activity", headers: auth_header(@admin_token)
      assert_response :success
      data = response.parsed_body["data"]
      summary = data["summary"]

      assert_operator summary["cases_created"], :>=, 1
      assert_operator summary["cases_resolved"], :>=, 1
      assert summary.key?("resolution_rate")
      assert summary.key?("sla_compliance")
      assert summary.key?("sla_breaches")
      assert data["actions_by_user"].any? { |row| row["name"] == users(:agent_a).name }
      assert data["volume_by_queue"].is_a?(Array)
    end

    test "activity report respects audit:read scope and denies others" do
      get "/api/v1/reports/activity", headers: auth_header(service_token_for(%w[audit:read]))
      assert_response :success

      get "/api/v1/reports/activity", headers: auth_header(service_token_for(%w[cases:read]))
      assert_response :forbidden

      get "/api/v1/reports/activity", headers: auth_header(api_token_for(users(:supervisor)))
      assert_response :forbidden
    end

    test "sla compliance counts breached resolutions against the rate" do
      kase = Case.create!(subject: "Breached then resolved", contact: contacts(:asha),
                          sla_policy: sla_policies(:standard))
      kase.update_columns(resolution_due_at: 2.hours.ago)
      SlaBreachSweepJob.perform_now
      kase.reload.transition_to!(:triaged)
      kase.transition_to!(:in_progress)
      kase.transition_to!(:resolved)

      report = ActivityReport.new(from: Date.current, to: Date.current)
      assert_operator report.stats[:sla_breaches], :>=, 1
      assert report.stats[:sla_compliance] < 100.0 if report.stats[:cases_resolved] == 1
    end
  end
end
