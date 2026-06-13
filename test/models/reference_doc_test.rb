require "test_helper"

class ReferenceDocTest < ActiveSupport::TestCase
  test "an attached file must be an extractable type (L)" do
    doc = ReferenceDoc.new(title: "Bad attachment", body: "pasted content")
    doc.file.attach(io: StringIO.new("PK\x03\x04"), filename: "evil.zip", content_type: "application/zip")
    assert_not doc.valid?
    assert doc.errors[:file].any?
  end

  test "an extractable attachment passes validation (L)" do
    doc = ReferenceDoc.new(title: "Good attachment", body: "pasted content")
    doc.file.attach(io: StringIO.new("hello"), filename: "note.txt", content_type: "text/plain")
    assert doc.valid?
  end

  # --- article lifecycle (PG3) ---

  test "generates a unique per-tenant slug from the title" do
    a = ReferenceDoc.create!(title: "Pension Arrears FAQ", body: "x")
    assert_equal "pension-arrears-faq", a.slug
    b = ReferenceDoc.create!(title: "Pension Arrears FAQ!", body: "y")
    assert_equal "pension-arrears-faq-2", b.slug, "collides on the parameterized base → suffixed"
  end

  test "the slug follows a title change" do
    doc = ReferenceDoc.create!(title: "Old", body: "x")
    doc.update!(title: "New Title")
    assert_equal "new-title", doc.slug
  end

  test "defaults to published + internal (grounds, not public)" do
    doc = ReferenceDoc.create!(title: "Defaulty", body: "x")
    assert doc.status_published?
    assert doc.visibility_internal?
  end

  test "grounding excludes drafts; public_kb is published + public only" do
    pub      = ReferenceDoc.create!(title: "Public Guide", body: "a", status: :published, visibility: :public)
    internal = ReferenceDoc.create!(title: "Internal SOP", body: "b", status: :published, visibility: :internal)
    draft    = ReferenceDoc.create!(title: "Draft Note", body: "c", status: :draft, visibility: :public)

    assert_includes ReferenceDoc.grounding, pub
    assert_includes ReferenceDoc.grounding, internal
    refute_includes ReferenceDoc.grounding, draft

    assert_equal [ pub ], ReferenceDoc.public_kb.to_a
  end
end
