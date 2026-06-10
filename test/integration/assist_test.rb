require "test_helper"

class AssistTest < ActionDispatch::IntegrationTest
  setup do
    Setting.set("llm_provider", "fake")
  end

  teardown do
    Setting.unset("llm_provider")
  end

  test "summarise renders an ephemeral summary" do
    sign_in_as users(:agent_a)
    post case_assist_summarise_path(cases(:pension_case))
    assert_response :success
    assert_match "Summary:", response.body
    assert_no_difference "Message.count" do
      post case_assist_summarise_path(cases(:pension_case))
    end
  end

  test "suggest reply renders insert-and-edit suggestion" do
    sign_in_as users(:agent_a)
    post case_assist_suggest_reply_path(cases(:pension_case))
    assert_response :success
    assert_match I18n.t("assist.insert_suggestion"), response.body
  end

  test "suggested-reply usage is noted in message metadata" do
    sign_in_as users(:agent_a)
    post case_messages_path(cases(:pension_case)), params: {
      ai_suggested: "true",
      message: { body: "Edited suggestion text", kind: "public_reply" }
    }
    assert Message.order(:id).last.metadata["ai_suggested"]
  end

  test "assist endpoints 404 when ai is off" do
    Setting.set("llm_provider", "off")
    sign_in_as users(:agent_a)
    post case_assist_summarise_path(cases(:pension_case))
    assert_response :not_found
  end

  test "readonly cannot request reply suggestions" do
    sign_in_as users(:readonly)
    post case_assist_suggest_reply_path(cases(:pension_case))
    assert_response :forbidden
  end

  test "api assist parity" do
    token = api_token_for(users(:admin))
    post "/api/v1/cases/#{cases(:pension_case).id}/assist/summarise", headers: auth_header(token)
    assert_response :success
    assert response.parsed_body["data"]["summary"].present?

    post "/api/v1/cases/#{cases(:pension_case).id}/assist/suggest_reply", headers: auth_header(token)
    assert response.parsed_body["data"]["suggestion"].present?
  end
end
