require "test_helper"

class RetrievalTest < ActiveSupport::TestCase
  test "grounding excludes drafts and includes published (both visibilities)" do
    ReferenceDoc.create!(title: "Draft SOP", body: "Pension arrears corrected in three days", status: :draft)
    assert_empty Retrieval.grounding_for("pension arrears"), "a draft must not ground the AI"

    ReferenceDoc.create!(title: "Live SOP", body: "Pension arrears corrected in three days", status: :published)
    assert Retrieval.grounding_for("pension arrears").any?, "a published doc grounds"
  end

  test "search_articles over public_kb returns only published public articles" do
    public_doc = ReferenceDoc.create!(title: "Refund window", body: "Refunds within seven days",
                                      status: :published, visibility: :public)
    ReferenceDoc.create!(title: "Refund internal", body: "Refunds within seven days",
                         status: :published, visibility: :internal)

    results = Retrieval.search_articles("refunds", scope: ReferenceDoc.public_kb)
    assert_equal [ public_doc ], results
  end

  test "a blank query falls back to the scope's listing" do
    a = ReferenceDoc.create!(title: "Alpha", body: "x", status: :published, visibility: :public)
    b = ReferenceDoc.create!(title: "Beta", body: "y", status: :published, visibility: :public)
    results = Retrieval.search_articles("", scope: ReferenceDoc.public_kb)
    assert_includes results, a
    assert_includes results, b
  end
end
