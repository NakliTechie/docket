require "application_system_test_case"

# The customer's whole self-service journey, driven in a REAL browser.
#
# This exists because the integration tests could not catch what broke here.
# `Portal::TrackingController#show` and `#reply` answer 200 on a POST, and Turbo
# discards a 200 form response ("Form responses must redirect to another
# location"). The server rendered the case correctly the whole time — the
# browser threw it away — so a request-level test asserting on the response body
# passed while the feature was dead for every actual customer.
#
# Only a browser reproduces it, which is why these assertions are here and not
# in test/integration/portal_flow_test.rb.
class PortalTrackingTest < ApplicationSystemTestCase
  setup do
    skip "No Chrome/Chromium available (set BROWSER_PATH)" unless self.class.browser_path
  end

  test "a customer files a case, looks it up, and replies" do
    visit portal_root_path

    fill_in "portal_submission[name]", with: "Kavya Reddy"
    fill_in "portal_submission[email]", with: "kavya.reddy@example.test"
    fill_in "portal_submission[subject]", with: "Invoice shows the wrong GST rate"
    fill_in "portal_submission[description]",
            with: "Our March invoice applied 18% GST where our contract says 12%."
    click_on I18n.t("portal.cases.new.submit")

    tracking_id = find("[data-test-id=tracking-id]").text.strip
    assert_match(/\ADKT-[A-Z0-9]{4}-[A-Z0-9]{4}\z/, tracking_id,
      "the confirmation must show a tracking ID")

    # Follow the real confirmation handoff. The just-created tracking ID is
    # carried server-side (never in the URL or Referer) so the customer cannot
    # lose it merely by following the primary action.
    click_on I18n.t("portal.cases.confirmation.track_now")
    assert_field "tracking_id", with: tracking_id
    fill_in "contact_email", with: "kavya.reddy@example.test"
    click_on I18n.t("portal.tracking.new.check")

    assert_text "Invoice shows the wrong GST rate"
    assert_text tracking_id
    assert_text "Our March invoice applied 18% GST"

    # The reply. Before the fix this saved the message but never updated the
    # thread, so it looked like nothing had happened.
    fill_in "body", with: "Adding our contract reference: ACME-2024-GST-12."
    click_on I18n.t("portal.tracking.show.send_reply")

    assert_text "Adding our contract reference: ACME-2024-GST-12."
    assert_no_text "Form responses must redirect"
  end

  test "a wrong challenge answer is refused without revealing the case" do
    kase = cases(:pension_case)

    visit portal_track_path
    fill_in "tracking_id", with: kase.tracking_id
    fill_in "contact_email", with: "not-the-contact@example.test"
    click_on I18n.t("portal.tracking.new.check")

    assert_text I18n.t("portal.tracking.not_found")
    assert_no_text kase.subject
  end
end
