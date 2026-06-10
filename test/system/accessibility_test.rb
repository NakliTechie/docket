require "application_system_test_case"

# WCAG 2.1 AA tooling pass (handoff §7): axe-core (vendored, MPL-2.0)
# runs against every major surface and the suite fails on any violation
# of the wcag2a/wcag2aa/wcag21a/wcag21aa rule sets.
class AccessibilityTest < ApplicationSystemTestCase
  AXE_SOURCE = File.read(Rails.root.join("test/support/axe.min.js"))

  setup do
    skip "No Chrome/Chromium available (set BROWSER_PATH)" unless self.class.browser_path
  end

  def assert_no_axe_violations(context = "document")
    page.driver.execute_script(AXE_SOURCE)
    results = page.driver.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      axe.run(document, {
        runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"] }
      }).then(r => done(r.violations.map(v => ({
        id: v.id, impact: v.impact, help: v.help,
        nodes: v.nodes.slice(0, 3).map(n => n.html.slice(0, 160))
      })))).catch(e => done([{ id: "axe-error", help: String(e) }]));
    JS
    messages = results.map { |v| "#{v["id"]} (#{v["impact"]}): #{v["help"]}\n    #{Array(v["nodes"]).join("\n    ")}" }
    assert_empty results, "axe violations on #{context}:\n  #{messages.join("\n  ")}"
  end

  test "staff console pages pass axe" do
    sign_in_with_form users(:admin)

    visit cases_path
    assert_no_axe_violations "cases index"

    visit case_path(cases(:pension_case))
    assert_no_axe_violations "case show"

    visit new_case_path
    assert_no_axe_violations "case form"

    visit contacts_path
    assert_no_axe_violations "contacts index"

    visit admin_settings_path
    assert_no_axe_violations "admin settings"

    visit admin_activity_path
    assert_no_axe_violations "activity view"
  end

  test "auth and portal pages pass axe" do
    visit new_session_path
    assert_no_axe_violations "sign in"

    visit portal_root_path
    assert_no_axe_violations "portal form"

    visit portal_track_path
    assert_no_axe_violations "portal tracking"
  end

  test "help modal passes axe while open" do
    sign_in_with_form users(:admin)
    visit cases_path
    page.driver.browser.keyboard.type("?")
    assert_selector "#help-modal[open]"
    assert_no_axe_violations "help modal open"
  end
end
