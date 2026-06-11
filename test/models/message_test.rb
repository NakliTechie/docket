require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "outbound public reply stamps first response on the case" do
    kase = cases(:pension_case)
    assert_nil kase.first_responded_at
    Message.create!(case: kase, kind: :public_reply, direction: :outbound,
                    author: users(:agent_a), body: "We are on it.")
    assert kase.reload.first_responded_at.present?
  end

  test "internal notes do not stamp first response" do
    kase = cases(:pension_case)
    Message.create!(case: kase, kind: :internal_note, direction: :outbound,
                    author: users(:agent_a), body: "Checking internally.")
    assert_nil kase.reload.first_responded_at
  end

  test "agent turns count as first response" do
    kase = cases(:pension_case)
    Message.create!(case: kase, kind: :agent_turn, direction: :outbound, body: "AI answer.")
    assert kase.reload.first_responded_at.present?
  end

  test "citizen reply moves waiting case back to in_progress" do
    kase = cases(:waiting_case)
    Message.create!(case: kase, kind: :public_reply, direction: :inbound,
                    author: contacts(:asha), body: "Here is the info you asked for.")
    assert_equal "in_progress", kase.reload.status
  end

  test "citizen reply does not move other statuses" do
    kase = cases(:assigned_case)
    Message.create!(case: kase, kind: :public_reply, direction: :inbound,
                    author: contacts(:ravi), body: "Any update?")
    assert_equal "in_progress", kase.reload.status
  end

  test "citizen reply on a resolved case reopens it (M13)" do
    kase = cases(:resolved_case)
    Message.create!(case: kase, kind: :public_reply, direction: :inbound,
                    author: kase.contact, body: "This still isn't fixed.")
    assert_equal "reopened", kase.reload.status
  end

  test "system author displays i18n label" do
    message = Message.new(body: "x")
    assert_equal I18n.t("messages.author.system"), message.author_display_name
  end
end
