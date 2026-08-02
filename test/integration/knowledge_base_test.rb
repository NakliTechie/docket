require "test_helper"

# PG3 — the knowledge-base product surfaces: the public customer portal KB, the
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

  test "an admin can inspect versions add a translation and retire an article" do
    sign_in_as users(:client_admin)
    doc = ReferenceDoc.create!(title: "Version history", body: "one", status: :published)
    doc.update!(body: "two")

    get admin_reference_doc_path(doc)
    assert_response :success
    assert_select "summary", text: "v2 · current"
    assert_select "summary", text: "v1"

    post admin_reference_docs_path, params: { reference_doc: {
      title: "संस्करण इतिहास", body: "दो", locale: "hi",
      translation_key: doc.translation_key, status: "draft"
    } }
    assert_response :redirect
    assert_equal [ "hi" ], doc.translations.pluck(:locale)

    post retire_admin_reference_doc_path(doc)
    assert_response :redirect
    assert doc.reload.status_retired?
    assert_equal 3, doc.version_number
  end

  test "an admin can build nested knowledge categories" do
    sign_in_as users(:client_admin)
    post admin_knowledge_categories_path,
         params: { knowledge_category: { name: "Benefits", position: 1 } }
    root = KnowledgeCategory.find_by!(name: "Benefits")
    post admin_knowledge_categories_path,
         params: { knowledge_category: { name: "Pensions", parent_id: root.id, position: 2 } }

    assert_response :redirect
    get admin_knowledge_categories_path
    assert_response :success
    assert_select "td", text: "Benefits / Pensions"
  end

  test "deleting a knowledge category detaches its articles with a new version" do
    sign_in_as users(:client_admin)
    category = KnowledgeCategory.create!(name: "Temporary topic")
    article = ReferenceDoc.create!(title: "Categorised", body: "x", knowledge_category: category)

    assert_difference -> { article.reload.version_number }, 1 do
      delete admin_knowledge_category_path(category)
    end
    assert_response :see_other
    assert_nil article.reload.knowledge_category
  end

  test "a portal visitor can change one helpfulness rating per article version" do
    article = public_article

    assert_difference "ReferenceDocRating.count", 1 do
      post rate_portal_kb_path(article.slug), params: { helpful: "true" }
    end
    assert_response :redirect
    assert_equal 100, article.helpfulness_summary[:score]

    assert_no_difference "ReferenceDocRating.count" do
      post rate_portal_kb_path(article.slug), params: { helpful: "false" }
    end
    assert_equal 0, article.helpfulness_summary[:score]

    get portal_kb_path(article.slug)
    assert_select "#helpfulness", text: /0 of 1 readers/
  end
end
