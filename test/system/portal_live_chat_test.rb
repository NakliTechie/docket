require "application_system_test_case"

class PortalLiveChatSystemTest < ApplicationSystemTestCase
  setup do
    skip "No Chrome/Chromium available (set BROWSER_PATH)" unless self.class.browser_path
  end

  test "customer starts a chat and sends another message without navigation" do
    visit new_portal_live_chat_path

    fill_in "live_chat_submission[name]", with: "Nandini"
    fill_in "live_chat_submission[email]", with: "nandini.chat@example.test"
    fill_in "live_chat_submission[message]", with: "I need help with a delayed refund"
    click_on I18n.t("portal.live_chats.new.start")

    assert_text I18n.t("portal.live_chats.show.title")
    assert_text "I need help with a delayed refund"

    fill_in "body", with: "The reference is REF-2026-100"
    click_on I18n.t("portal.live_chats.show.send")

    assert_text "The reference is REF-2026-100"
    assert_current_path portal_live_chat_path
  end
end
