require "application_system_test_case"

class KeyboardWorkspaceTest < ApplicationSystemTestCase
  setup do
    skip "No Chrome/Chromium available (set BROWSER_PATH)" unless self.class.browser_path
  end

  test "j/k selects and Enter opens a case from the list" do
    sign_in_with_form users(:admin)
    visit cases_path(sort: "created_at", dir: "asc")

    page.driver.browser.keyboard.type("j")
    assert_selector "tr.row-selected", count: 1
    first_subject = find("tr.row-selected td:nth-child(2)").text

    page.driver.browser.keyboard.type("j")
    second_subject = find("tr.row-selected td:nth-child(2)").text
    refute_equal first_subject, second_subject

    page.driver.browser.keyboard.type("k")
    assert_equal first_subject, find("tr.row-selected td:nth-child(2)").text

    page.driver.browser.keyboard.type(:enter)
    assert_selector "h1", text: first_subject
  end

  test "question mark opens the documented help modal" do
    sign_in_with_form users(:admin)
    visit cases_path
    page.driver.browser.keyboard.type("?")
    assert_selector "#help-modal[open]"
    assert_text I18n.t("help.bindings.next_case")
  end

  test "single-key status shortcut transitions the case" do
    sign_in_with_form users(:admin)
    visit case_path(cases(:pension_case))
    page.driver.browser.keyboard.type("t")
    assert_text I18n.t("cases.transition.transitioned", status: I18n.t("cases.enum.status.triaged"))
    assert_equal "triaged", cases(:pension_case).reload.status
  end

  test "a assigns the case to me" do
    sign_in_with_form users(:admin)
    visit case_path(cases(:pension_case))
    page.driver.browser.keyboard.type("a")
    assert_equal users(:admin), cases(:pension_case).reload.assignee
  end

  test "command palette jumps to a queue" do
    sign_in_with_form users(:admin)
    visit contacts_path
    find("body").send_keys([ :control, "k" ])
    assert_selector "#command-palette[open]"
    find("#command-palette input").fill_in(with: "Pensions")
    page.driver.browser.keyboard.type(:enter)
    assert_current_path cases_path(queue_id: queues(:pensions).id)
  end

  test "shortcuts stay quiet while typing" do
    sign_in_with_form users(:admin)
    visit case_path(cases(:pension_case))
    find("textarea[data-shortcut=m]").click
    page.driver.browser.keyboard.type("t")
    assert_equal "new", cases(:pension_case).reload.status
  end
end
