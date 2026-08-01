require "test_helper"

class SequenceUnsubscribesTest < ActionDispatch::IntegrationTest
  test "the signed public flow confirms and completes without a staff session" do
    lead = Lead.create!(name: "Public unsubscribe", email: "public-unsubscribe@example.test",
                        email_consent: true)
    token = SequenceUnsubscribe.token_for(lead)

    get sequence_unsubscribe_path(token: token)
    assert_response :success
    assert_match I18n.t("sequence_unsubscribes.show.confirm"), response.body

    post sequence_unsubscribe_path(token: token)
    assert_response :success
    assert_match I18n.t("sequence_unsubscribes.success.title"), response.body
    refute lead.reload.email_consent?
  end

  test "an invalid public token reveals no target" do
    get sequence_unsubscribe_path(token: "invalid")
    assert_response :not_found
    post sequence_unsubscribe_path(token: "invalid")
    assert_response :not_found
  end
end
