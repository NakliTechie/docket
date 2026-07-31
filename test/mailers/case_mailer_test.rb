require "test_helper"

class CaseMailerTest < ActionMailer::TestCase
  test "a public reply carries safe RFC thread headers from inbound email" do
    kase = cases(:pension_case)
    kase.messages.create!(body: "Inbound", direction: :inbound, kind: :public_reply,
                          author: kase.contact, email_message_id: "customer-thread@example.test")
    reply = kase.messages.create!(body: "Staff response", direction: :outbound,
                                  kind: :public_reply, author: users(:agent_a))

    mail = CaseMailer.public_reply(reply)

    assert_equal "<customer-thread@example.test>", mail["In-Reply-To"].value
    assert_includes mail["References"].value, "<customer-thread@example.test>"
  end

  test "malformed stored message ids cannot inject mail headers" do
    kase = cases(:pension_case)
    kase.messages.create!(body: "Inbound", direction: :inbound, kind: :public_reply,
                          author: kase.contact,
                          email_message_id: "safe@example.test\r\nBcc: attacker@example.test")
    reply = kase.messages.create!(body: "Staff response", direction: :outbound,
                                  kind: :public_reply, author: users(:agent_a))

    mail = CaseMailer.public_reply(reply)

    assert_nil mail["In-Reply-To"]
    assert_nil mail["References"]
    refute_includes mail.encoded, "attacker@example.test"
  end

  test "a public reply preserves attachments and renders safe rich text with its signature" do
    reply = cases(:pension_case).messages.create!(
      body: "**Resolved** [details](https://example.test/help) <script>alert(1)</script>",
      direction: :outbound, kind: :public_reply, author: users(:admin),
      metadata: { "signature" => "**Anita**" }
    )
    reply.files.attach(io: StringIO.new("evidence"), filename: "evidence.txt",
                       content_type: "text/plain")

    mail = CaseMailer.public_reply(reply)
    assert_equal [ "evidence.txt" ], mail.attachments.map(&:filename)
    html = mail.html_part.body.decoded
    assert_includes html, "<strong>Resolved</strong>"
    assert_includes html, "<strong>Anita</strong>"
    refute_includes html, "<script>"
    assert_includes html, "&lt;script&gt;"
  end
end
