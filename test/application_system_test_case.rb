require "test_helper"
require "capybara/cuprite"

# System tests run on Cuprite (CDP — no chromedriver needed). Point
# BROWSER_PATH at a Chrome/Chromium binary; common install locations
# are auto-detected.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  BROWSER_CANDIDATES = [
    ENV["BROWSER_PATH"],
    "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/usr/bin/google-chrome",
    # macOS (developer machines) — without these the whole system suite
    # silently skips locally and only ever runs in CI.
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium"
  ].compact.freeze

  def self.browser_path
    @browser_path ||= BROWSER_CANDIDATES.find { |path| File.executable?(path) }
  end

  Capybara.register_driver(:docket_cuprite) do |app|
    Capybara::Cuprite::Driver.new(
      app,
      browser_path: browser_path,
      window_size: [ 1400, 900 ],
      browser_options: { "no-sandbox" => nil, "disable-dev-shm-usage" => nil },
      process_timeout: 30,
      timeout: 20
    )
  end

  driven_by :docket_cuprite

  def sign_in_with_form(user, password: "password")
    visit new_session_path
    fill_in I18n.t("sessions.new.email"), with: user.email_address
    fill_in I18n.t("sessions.new.password"), with: password
    click_button I18n.t("sessions.new.sign_in")
    # Since ENT, "/" is a redirector to whichever surface the tenant actually
    # has, so a signed-in browser never rests on root. Assert we left the
    # sign-in page rather than pinning a destination that now varies by
    # entitlement.
    assert_no_current_path new_session_path
  end
end
