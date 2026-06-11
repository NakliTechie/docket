require "test_helper"

class PortalSubmissionTest < ActiveSupport::TestCase
  def submit(name:, email: nil, phone: nil, subject: "Issue", description: "Details")
    PortalSubmission.new(name: name, email: email, phone: phone, subject: subject, description: description).save
  end

  test "requires name, subject, description and a way to reach the citizen" do
    assert_not PortalSubmission.new(name: "X", subject: "S", description: "D").save # no email/phone
    assert submit(name: "Reachable", email: "reachable@example.com")
  end

  test "an anonymous submission matching a verified (SSO) contact does NOT attach to it (M9)" do
    verified = Contact.create!(name: "SSO Customer", email: "sso.cust@example.com", external_id: "CIF-VERIFIED-1")

    kase = nil
    assert_difference "Contact.count", 1 do # a fresh contact, not the verified one
      kase = submit(name: "Imposter", email: "sso.cust@example.com", subject: "Injected")
    end
    assert kase
    assert_not_equal verified, kase.contact, "must not attach to a verified contact by email match"
    assert_nil kase.contact.external_id
  end

  test "anonymous submissions still dedupe onto an unverified contact" do
    unverified = Contact.create!(name: "Repeat Filer", email: "repeat@example.com")
    kase = nil
    assert_no_difference "Contact.count" do
      kase = submit(name: "Repeat Filer", email: "repeat@example.com", subject: "Again")
    end
    assert_equal unverified, kase.contact
  end
end
