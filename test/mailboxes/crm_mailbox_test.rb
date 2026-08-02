require "test_helper"

class CrmMailboxTest < ActionMailbox::TestCase
  test "a staff BCC records outbound mail without opening a case" do
    deal = Deal.create!(name: "BCC deal", pipeline: pipelines(:sales), contact: contacts(:asha))
    assert_operator CrmMailboxAddress.address_for(deal).split("@").first.length, :<=, 64

    assert_no_difference "Case.count" do
      assert_difference "CrmMessage.count", 1 do
        receive_inbound_email_from_mail(
          from: users(:sales).email_address, to: contacts(:asha).email,
          bcc: CrmMailboxAddress.address_for(deal), subject: "Sent proposal", body: "Please review."
        )
      end
    end

    message = CrmMessage.order(:id).last
    assert message.direction_outbound?
    assert message.delivery_status_recorded?
    assert_equal deal, message.subject
    assert_equal users(:sales), message.author
  end

  test "a customer reply to the CRM address records inbound mail" do
    lead = Lead.create!(name: "Reply lead", email: "reply.lead@example.test")

    assert_difference "CrmMessage.count", 1 do
      receive_inbound_email_from_mail(
        from: lead.email, to: CrmMailboxAddress.address_for(lead),
        subject: "Re: proposal", body: "Please call tomorrow."
      )
    end

    message = CrmMessage.order(:id).last
    assert message.direction_inbound?
    assert_equal lead, message.subject
    assert_nil message.author
  end

  test "an unrelated sender cannot inject into a CRM thread" do
    lead = Lead.create!(name: "Protected lead", email: "protected@example.test")
    inbound = create_inbound_email_from_source(
      Mail.new(from: "attacker@example.test", to: CrmMailboxAddress.address_for(lead),
               subject: "Forged", body: "Advance this deal").to_s
    )

    assert_no_difference "CrmMessage.count" do
      inbound.route
    end
    assert inbound.bounced?
  end

  test "a tampered CRM address bounces" do
    address = CrmMailboxAddress.address_for(contacts(:asha)).sub(/.(?=@)/, "x")
    inbound = create_inbound_email_from_source(
      Mail.new(from: contacts(:asha).email, to: address, subject: "Forged", body: "No").to_s
    )

    assert_no_difference "CrmMessage.count" do
      inbound.route
    end
    assert inbound.bounced?
  end
end
