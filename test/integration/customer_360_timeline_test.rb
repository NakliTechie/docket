require "test_helper"

# A1: the contact/organisation workspace renders the unified chronological
# timeline (the vision's "single view"), not only the summary tiles.
class Customer360TimelineTest < ActionDispatch::IntegrationTest
  test "the contact workspace renders the unified activity timeline" do
    sign_in_as users(:admin)
    contact = contacts(:asha)
    kase = Case.create!(subject: "Timeline case", contact: contact)
    kase.messages.create!(kind: :public_reply, direction: :inbound, body: "hello", author: contact)

    get contact_path(contact)
    assert_response :success
    assert_select "h3.panel-title", text: I18n.t("customer_360.timeline")
    assert_select "ol.c360-timeline .c360-event", minimum: 2
    assert_select ".c360-event .c360-kind", text: I18n.t("customer_360.events.case_opened")
    assert_select ".c360-event .c360-kind", text: I18n.t("customer_360.events.message")
  end

  test "an organisation workspace also renders the timeline" do
    sign_in_as users(:admin)
    org = organisations(:dpg)
    get organisation_path(org)
    assert_response :success
    assert_select "h3.panel-title", text: I18n.t("customer_360.timeline")
  end
end
