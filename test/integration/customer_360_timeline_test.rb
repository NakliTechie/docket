require "test_helper"

# A1: the contact/organisation workspace renders the unified chronological
# timeline (the vision's "single view"), not only the summary tiles.
class Customer360TimelineTest < ActionDispatch::IntegrationTest
  def create_sequence_touch(target, marker: "Sequence timeline marker")
    sequence = Sequence.new(name: "Timeline cadence")
    step = sequence.sequence_steps.build(position: 0, delay_days: 0,
                                         subject: marker, body: "Hello")
    sequence.save!
    enrollment = sequence.enroll!(target)
    SequenceDelivery.create!(
      sequence_enrollment: enrollment, sequence_step: step, channel: "email",
      recipient: target.email, status: :delivered, delivered_at: Time.current,
      payload: { "subject" => marker, "body" => "Hello" }
    )
  end

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

  test "a message body with an apostrophe is not double-escaped in the timeline" do
    sign_in_as users(:admin)
    contact = contacts(:asha)
    kase = Case.create!(subject: "Apostrophe case", contact: contact)
    kase.messages.create!(kind: :public_reply, direction: :inbound,
                          body: "We can't log in", author: contact)

    get contact_path(contact)
    assert_response :success
    # Correct single-escape renders as &#39; (browser shows "can't").
    # A double-escape (&amp;#39;) shows the literal entity — regression guard.
    assert_not_includes response.body, "&amp;#39;",
                        "message body must be single-escaped, not double-escaped"
  end

  test "a sequence reader sees delivered touches in contact and organisation timelines" do
    sign_in_as users(:sales)
    contact = contacts(:asha)
    create_sequence_touch(contact)

    get contact_path(contact)
    assert_response :success
    assert_select ".c360-event-sequence_email", text: /Sequence timeline marker/

    get organisation_path(contact.organisation)
    assert_response :success
    assert_select ".c360-event-sequence_email", text: /Sequence timeline marker/
  end

  test "a contact reader without sequence visibility cannot see sequence touches" do
    sign_in_as users(:customer_service)
    contact = contacts(:asha)
    create_sequence_touch(contact, marker: "Restricted sequence marker")

    get contact_path(contact)

    assert_response :success
    refute_includes response.body, "Restricted sequence marker"
  end

  test "the sequence sub-feature contains timeline touches" do
    create_sequence_touch(contacts(:asha), marker: "Disabled sequence marker")
    ActsAsTenant.current_tenant.set_feature!("crm.sequences", false)
    sign_in_as users(:admin)

    get contact_path(contacts(:asha))

    assert_response :success
    refute_includes response.body, "Disabled sequence marker"
  end
end
