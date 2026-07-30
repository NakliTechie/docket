require "application_system_test_case"

class NewcomerUxTest < ApplicationSystemTestCase
  setup do
    skip "No Chrome/Chromium available (set BROWSER_PATH)" unless self.class.browser_path
  end

  test "setup exposes and copies the portal handoff" do
    sign_in_with_form users(:admin)
    visit setup_path

    assert_text I18n.t("setups.show.title")
    click_button I18n.t("setups.show.portal.copy")
    assert_text I18n.t("setups.show.portal.copied")
    assert_link I18n.t("setups.show.portal.open"), href: portal_root_path
  end

  test "staff create a first contact inline and keep the case details" do
    sign_in_with_form users(:customer_service)
    visit new_case_path

    fill_in "case[subject]", with: "Browser first request"
    fill_in "case[description]", with: "This text must survive contact creation."
    details = find("details.inline-contact")
    details.find("summary").click unless details[:open]
    fill_in "new_contact[name]", with: "Browser Customer"
    fill_in "new_contact[email]", with: "browser.customer@example.test"
    find("input[type=submit].btn-primary").click

    assert_text "Browser first request"
    assert_text "This text must survive contact creation."
    assert_text "Browser Customer"
  end

  test "mobile navigation stays within the viewport and opens one group at a time" do
    page.current_window.resize_to(390, 844)
    sign_in_with_form users(:admin)
    visit cases_path

    assert_no_selector ".case-table thead", visible: true
    assert_selector ".case-table td[data-label]"
    click_button I18n.t("layout.nav.menu")
    assert_selector ".app-nav.menu-open"
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=,
                    page.evaluate_script("window.innerWidth")

    customers = find("summary", text: I18n.t("layout.nav.customers"))
    administration = find("summary", text: I18n.t("layout.nav.administration"))
    customers.click
    assert customers.find(:xpath, "..")[:open]
    administration.click
    refute customers.find(:xpath, "..")[:open]
    assert administration.find(:xpath, "..")[:open]
  end

  test "Turbo navigation emits no content-security-policy console error" do
    messages = []
    page.driver.browser.on(:console) do |type, args|
      messages << [ type, args.map { |arg| arg.respond_to?(:value) ? arg.value : arg.to_s }.join(" ") ]
    end

    visit portal_root_path
    click_link I18n.t("portal.nav.track")

    violations = messages.select { |_, message| message.match?(/content security policy|refused to apply.*style/i) }
    assert_empty violations, "CSP console errors: #{violations.inspect}"
  end
end
