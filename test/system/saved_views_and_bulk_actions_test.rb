require "application_system_test_case"

class SavedViewsAndBulkActionsSystemTest < ApplicationSystemTestCase
  setup do
    skip "No Chrome/Chromium available (set BROWSER_PATH)" unless self.class.browser_path
  end

  test "an agent saves a filtered inbox and bulk-updates selected cases" do
    sign_in_with_form users(:admin)
    visit cases_path(priority: "normal")

    within ".saved-view-create" do
      fill_in I18n.t("saved_views.name"), with: "Normal inbox"
      click_button I18n.t("saved_views.save")
    end
    assert_selector "select[name='saved_view_id'] option[selected]", text: "Normal inbox"

    selected_case = cases(:pension_case)
    find("input[name='case_ids[]'][value='#{selected_case.id}']").check
    within ".bulk-action-bar" do
      select I18n.t("bulk_actions.priority"), from: "case_bulk_action"
      select I18n.t("cases.enum.priority.urgent"), from: "case_bulk_priority"
      click_button I18n.t("bulk_actions.apply")
    end

    assert_text I18n.t("cases.bulk_update.updated", count: 1, submitted: 0)
    assert selected_case.reload.priority_urgent?
  end
end
