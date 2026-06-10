require "test_helper"

class CaseAgentTest < ActiveSupport::TestCase
  setup do
    Setting.set("llm_provider", "fake")
    Setting.set("ai_draft_enabled", true)
  end

  teardown do
    Setting.unset("llm_provider")
  end

  def build_case(subject: "No water supply", description: "No water for two days")
    Case.create!(subject: subject, description: description,
                 contact: contacts(:asha), channel: :web_portal)
  end

  test "routes, triages, and drafts with full prompt/response logged" do
    kase = build_case
    CaseAgent.new(kase).run
    kase.reload

    assert_equal "triaged", kase.status
    assert kase.queue.present?

    notes = kase.messages.where(kind: :internal_note).order(:id)
    assert_equal %w[route draft], notes.map { |n| n.metadata["ai"] }
    notes.each do |note|
      assert note.metadata["prompt"].present?, "prompt must be logged"
      assert note.metadata["response"].present?, "response must be logged"
    end
  end

  test "draft stays internal when category has no auto-resolve" do
    kase = build_case
    CaseAgent.new(kase).run
    assert_empty kase.messages.where(kind: :agent_turn)
    refute kase.reload.status_resolved?
  end

  test "auto-resolves only with per-category opt-in and high confidence" do
    categories(:pension_delay).update!(ai_auto_resolve: true)
    # FakeClient routes to the first category alphabetically — make it ours.
    Category.where.not(id: categories(:pension_delay).id).find_each(&:destroy)

    kase = build_case(subject: "Pension delay", description: "Simple pension delay query")
    CaseAgent.new(kase).run
    kase.reload

    assert_equal "resolved", kase.status
    turn = kase.messages.where(kind: :agent_turn).first
    assert turn.present?, "resolve must create a public agent turn"
    assert_includes turn.body, I18n.t("cases.agent.human_handoff_footer")
  end

  test "low-confidence drafts do not auto-resolve even with opt-in" do
    categories(:pension_delay).update!(ai_auto_resolve: true)
    Category.where.not(id: categories(:pension_delay).id).find_each(&:destroy)

    # FakeClient flags "complex" content as low confidence.
    kase = build_case(subject: "Pension delay", description: "This is a complex legal matter")
    CaseAgent.new(kase).run
    refute kase.reload.status_resolved?
    assert_empty kase.messages.where(kind: :agent_turn)
  end

  test "agent does nothing when ai is off" do
    Setting.set("llm_provider", "off")
    kase = build_case
    CaseAgent.new(kase, client: Llm.client).run
    assert_equal "new", kase.reload.status
    assert_empty kase.messages
  end

  test "llm errors degrade to a logged note, case stays human" do
    failing = Object.new
    def failing.chat(*, **) = raise(Llm::Error, "endpoint down")

    kase = build_case
    CaseAgent.new(kase, client: failing).run
    kase.reload
    assert_equal "new", kase.status
    assert_equal "error", kase.messages.last.metadata["ai"]
  end

  test "agent skips cases that are not new" do
    kase = build_case
    kase.transition_to!(:triaged)
    assert_no_difference "Message.count" do
      CaseAgent.new(kase).run
    end
  end

  test "sentiment job flags inbound messages" do
    message = Message.create!(case: cases(:pension_case), kind: :public_reply,
                              direction: :inbound, author: contacts(:asha),
                              body: "This is unacceptable, I am furious!")
    SentimentJob.perform_now(message)
    assert_equal "negative", message.reload.sentiment
  end

  test "retrieval grounds on reference docs and closed cases" do
    ReferenceDoc.create!(title: "Pension SOP", body: "Pension arrears are corrected within 3 days.")
    results = Retrieval.grounding_for("pension arrears delay")
    assert results.any? { |r| r.source == "reference_doc" && r.title == "Pension SOP" }
  end
end
