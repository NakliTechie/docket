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

  test "creates immutable snapshots and advances the current version pointer" do
    doc = ReferenceDoc.create!(title: "Versioned guide", body: "First body", status: :draft)

    assert_equal 1, doc.version_number
    assert_equal "First body", doc.current_version.body

    first_version = doc.current_version
    doc.update!(body: "Second body", status: :published)

    assert_equal 2, doc.reload.version_number
    assert_equal "Second body", doc.current_version.body
    assert_equal "First body", first_version.reload.body
    assert_raises(ActiveRecord::ReadOnlyRecord) { first_version.update!(body: "Rewritten") }
  end

  test "links locale variants and selects the requested translation with fallback" do
    english = ReferenceDoc.create!(title: "Payments", body: "English", locale: "en",
                                   status: :published, visibility: :public)
    hindi = ReferenceDoc.create!(title: "भुगतान", body: "हिन्दी", locale: "hi",
                                 translation_key: english.translation_key,
                                 status: :published, visibility: :public)
    fallback = ReferenceDoc.create!(title: "Refunds", body: "English fallback", locale: "en",
                                    status: :published, visibility: :public)

    assert_equal [ hindi ], english.translations.to_a
    assert_equal [ hindi, fallback ].sort_by(&:title), ReferenceDoc.public_kb(:hi).to_a.sort_by(&:title)

    duplicate = ReferenceDoc.new(title: "दूसरा भुगतान", body: "x", locale: "hi",
                                 translation_key: english.translation_key)
    assert_not duplicate.valid?
    assert duplicate.errors[:translation_key].any?
  end

  test "retired articles leave grounding and public search" do
    doc = ReferenceDoc.create!(title: "Old policy", body: "x", status: :published, visibility: :public)
    doc.status_retired!

    refute_includes ReferenceDoc.grounding, doc
    refute_includes ReferenceDoc.public_kb, doc
    assert_equal 2, doc.version_number
  end

  test "helpfulness summary is scoped to the current version" do
    doc = ReferenceDoc.create!(title: "Rated guide", body: "x")
    doc.reference_doc_ratings.create!(reference_doc_version: doc.current_version,
                                      visitor_token_digest: "reader-a", helpful: true)
    doc.reference_doc_ratings.create!(reference_doc_version: doc.current_version,
                                      visitor_token_digest: "reader-b", helpful: false)

    assert_equal({ helpful: 1, unhelpful: 1, total: 2, score: 50 }, doc.helpfulness_summary)

    doc.update!(body: "new version")
    assert_equal({ helpful: 0, unhelpful: 0, total: 0, score: nil }, doc.helpfulness_summary)
  end

  test "rejects a current pointer to another article version" do
    first = ReferenceDoc.create!(title: "First pointer", body: "x")
    second = ReferenceDoc.create!(title: "Second pointer", body: "y")

    first.current_version = second.current_version
    assert_not first.valid?
    assert first.errors[:current_version].any?
  end
end
