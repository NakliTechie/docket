require "test_helper"

# PG3 — the knowledge-base product surfaces: the public citizen portal KB, the
# in-console staff search, and admin lifecycle controls.
class KnowledgeBaseTest < ActionDispatch::IntegrationTest
  def public_article
    ReferenceDoc.create!(title: "How refunds work", body: "Refunds are issued within seven days.",
                         status: :published, visibility: :public)
  end

  # --- public portal KB (unauthenticated) ---

  test "the portal KB lists only published public articles" do
    pub = public_article
    ReferenceDoc.create!(title: "Internal only", body: "staff procedure", status: :published, visibility: :internal)
    ReferenceDoc.create!(title: "Draft public", body: "wip", status: :draft, visibility: :public)

    get portal_kb_index_path
    assert_response :success
    assert_select "a", text: pub.title
    assert_select "a", text: "Internal only", count: 0
    assert_select "a", text: "Draft public", count: 0
  end

  test "a public article is readable by slug; internal/draft 404" do
    pub = public_article
    internal = ReferenceDoc.create!(title: "Internal", body: "x", status: :published, visibility: :internal)

    get portal_kb_path(pub.slug)
    assert_response :success
    assert_select "h1", text: pub.title

    get portal_kb_path(internal.slug)
    assert_response :not_found
  end

  test "the portal KB search finds a matching public article" do
    public_article
    get portal_kb_index_path(q: "refunds")
    assert_response :success
    assert_select "a", text: "How refunds work"
  end

  # --- in-console staff search ---

  test "an authenticated agent can search the KB and gets matching articles" do
    sign_in_as users(:customer_service)
    internal = ReferenceDoc.create!(title: "Pension SOP", body: "Arrears corrected in three days",
                                    status: :published, visibility: :internal)
    get knowledge_base_search_path(q: "pension arrears")
    assert_response :success
    assert_includes response.body, internal.title, "staff search includes internal articles"
  end

  test "the in-console search requires a logged-in staffer" do
    get knowledge_base_search_path(q: "anything")
    assert_response :redirect # bounced to login
  end

  # --- admin lifecycle ---

  test "an admin can toggle publish state and set visibility + category" do
    sign_in_as users(:client_admin)
    doc = ReferenceDoc.create!(title: "Lifecycle doc", body: "x", status: :draft)

    post toggle_published_admin_reference_doc_path(doc)
    assert doc.reload.status_published?
    post toggle_published_admin_reference_doc_path(doc)
    assert doc.reload.status_draft?

    patch admin_reference_doc_path(doc), params: { reference_doc: {
      visibility: "public", category_id: categories(:pension_delay).id, status: "published"
    } }
    doc.reload
    assert doc.visibility_public?
    assert_equal categories(:pension_delay), doc.category
  end

  test "lifecycle controls are gated on reference_doc:manage" do
    sign_in_as users(:customer_service)
    doc = ReferenceDoc.create!(title: "Guarded", body: "x")
    post toggle_published_admin_reference_doc_path(doc)
    assert_response :forbidden
  end
end
