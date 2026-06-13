require "test_helper"

class CasesMailboxTest < ActionMailbox::TestCase
  test "fresh email opens a case with contact and initial message" do
    assert_difference [ "Case.count", "Contact.count" ], 1 do
      receive_inbound_email_from_mail(
        from: '"Mohan Lal" <mohan@example.com>',
        to: "grievances@docket.local",
        subject: "ATM swallowed my card",
        body: "The ATM at Karol Bagh retained my card."
      )
    end
    kase = Case.order(:id).last
    assert_equal "email", kase.channel
    assert_equal "ATM swallowed my card", kase.subject
    assert_equal "mohan@example.com", kase.contact.email
    assert_equal "Mohan Lal", kase.contact.name
    assert_equal 1, kase.messages.count
    assert kase.messages.first.direction_inbound?
  end

  test "intake resolves the tenant itself with no ambient context (production isolated path)" do
    # Inbound mail runs outside any request/job, so no tenant is set — the
    # mailbox must resolve it (the singleton in isolated mode), or scoped
    # creates would fail. test_tenant masks this, so clear it here.
    ActsAsTenant.test_tenant = nil
    ActsAsTenant.current_tenant = nil
    assert_difference "Case.count", 1 do
      receive_inbound_email_from_mail(
        from: "newperson@example.com", to: "grievances@docket.local",
        subject: "No tenant set", body: "Body."
      )
    end
    assert_equal tenants(:primary), Case.order(:id).last.tenant
  ensure
    ActsAsTenant.test_tenant = tenants(:primary)
  end

  test "email from a known contact reuses the contact" do
    assert_no_difference "Contact.count" do
      receive_inbound_email_from_mail(
        from: contacts(:asha).email, to: "grievances@docket.local",
        subject: "Another matter", body: "Details."
      )
    end
    assert_equal contacts(:asha), Case.order(:id).last.contact
  end

  test "tracking id in subject threads onto the case for the matching sender" do
    kase = cases(:pension_case)
    assert_no_difference "Case.count" do
      assert_difference "kase.messages.count" do
        receive_inbound_email_from_mail(
          from: contacts(:asha).email, to: "grievances@docket.local",
          subject: "Re: Your case #{kase.tracking_id}", body: "Adding more information."
        )
      end
    end
  end

  test "tracking id from a non-matching sender opens a separate case" do
    kase = cases(:pension_case)
    assert_difference "Case.count" do
      assert_no_difference "kase.messages.count" do
        receive_inbound_email_from_mail(
          from: "attacker@example.com", to: "grievances@docket.local",
          subject: "Re: Your case #{kase.tracking_id}", body: "I am definitely the owner."
        )
      end
    end
  end

  test "citizen email reply moves waiting case back to in_progress" do
    kase = cases(:waiting_case)
    receive_inbound_email_from_mail(
      from: contacts(:asha).email, to: "grievances@docket.local",
      subject: "Re: #{kase.tracking_id}", body: "Requested details attached."
    )
    assert_equal "in_progress", kase.reload.status
  end

  test "disallowed attachment types are dropped, allowed kept" do
    mail = Mail.new do
      from "mohan@example.com"
      to "grievances@docket.local"
      subject "With attachments"
      body "See attached."
      add_file filename: "photo.png", content: "\x89PNG fake"
      add_file filename: "run.exe", content: "MZ fake"
    end
    mail.attachments[0].content_type = "image/png"
    mail.attachments[1].content_type = "application/x-msdownload"
    receive_inbound_email_from_source(mail.to_s)

    message = Case.order(:id).last.messages.first
    assert_equal [ "photo.png" ], message.files.map { |f| f.filename.to_s }
  end

  test "html-only email is converted to text" do
    mail = Mail.new do
      from "mohan@example.com"
      to "grievances@docket.local"
      subject "HTML only"
      content_type "text/html; charset=UTF-8"
      body "<p>Hello <strong>team</strong>,</p><p>My issue persists.</p><script>alert(1)</script>"
    end
    receive_inbound_email_from_source(mail.to_s)
    body = Case.order(:id).last.messages.first.body
    assert_includes body, "My issue persists."
    refute_includes body, "<p>"
    refute_includes body, "alert(1)"
  end

  test "a malformed From header bounces instead of crashing the intake (M15)" do
    assert_no_difference [ "Case.count", "Contact.count" ] do
      [ "plain text no brackets", "=?utf-8?Q?=ZZ?= <bad", "a@b@c <broken" ].each do |bad_from|
        inbound = create_inbound_email_from_source("From: #{bad_from}\r\nTo: grievances@docket.local\r\nSubject: x\r\n\r\nbody\r\n")
        assert_nothing_raised { inbound.route }
        assert inbound.bounced?, "#{bad_from.inspect} should bounce"
      end
    end
  end

  test "a valid From still opens a case (regression guard for M15)" do
    assert_difference "Case.count", 1 do
      receive_inbound_email_from_mail(
        from: "valid.person@example.com", to: "grievances@docket.local",
        subject: "Real", body: "Genuine."
      )
    end
  end
end
