require "test_helper"

class ContactTest < ActiveSupport::TestCase
  test "requires at least one reachable channel" do
    contact = Contact.new(name: "Nobody")
    refute contact.valid?
    assert contact.errors[:base].any?
  end

  test "external_id alone is sufficient" do
    assert Contact.new(name: "CIF Only", external_id: "CIF000001").valid?
  end

  test "normalizes email and phone" do
    contact = Contact.create!(name: "Norm", email: " UPPER@Example.COM ", phone: "98765-43210 ")
    assert_equal "upper@example.com", contact.email
    assert_equal "9876543210", contact.phone
  end

  test "external_id unique among live contacts" do
    dup = Contact.new(name: "Dup", external_id: contacts(:ravi).external_id)
    refute dup.valid?
    assert dup.errors[:external_id].any?
  end

  test "search matches name email phone and external id" do
    assert_includes Contact.search("asha"), contacts(:asha)
    assert_includes Contact.search("CIF447"), contacts(:ravi)
    assert_includes Contact.search("98765"), contacts(:ravi)
  end

  # M16 / ZD_10045: a % in the query is a LITERAL, not a wildcard. sanitize_sql_like
  # backslash-escapes it, but that only bites when the LIKE declares ESCAPE '\'
  # (SQLite's LIKE has no default escape char). Without the ESCAPE clause this
  # search returns the wrong set — the escaped "\%" becomes a required literal
  # backslash and the "100% cashback" row is missed.
  test "search treats % and _ as literals, not wildcards (LIKE ESCAPE)" do
    literal = Contact.create!(name: "100% cashback offer", email: "cashback@example.com")
    other   = Contact.create!(name: "100 rupees flat", email: "rupees@example.com")

    hits = Contact.search("100%")
    assert_includes hits, literal, "the literal % row must match"
    refute_includes hits, other, "% must not act as a wildcard"
  end
end
