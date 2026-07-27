require "test_helper"

# NC2 — the migration path off Netcore's current stack. Every importer works
# from an EXPORT FILE, so it runs with no vendor credentials, and every one
# defaults to a dry run that reports what it would do.
class ImportsTest < ActiveSupport::TestCase
  # ── Jira → work items ─────────────────────────────────────────────────────
  def jira_export(overrides = {})
    { "issues" => [ {
      "key" => "PEP-77",
      "fields" => {
        "summary" => "Payment webhook retries",
        "description" => "Retries stop after one attempt.",
        "issuetype" => { "name" => "Bug" },
        "priority" => { "name" => "Highest" },
        "status" => { "name" => "In Progress" },
        "timeoriginalestimate" => 18_000,
        "comment" => { "comments" => [ { "body" => "Reproduced on staging." } ] }
      }.merge(overrides)
    } ] }
  end

  test "a Jira issue becomes a work item, keeping its number" do
    result = Imports::Jira.call(payload: jira_export, project: projects(:pep), actor: users(:admin))

    assert_equal 1, result.created["issues"]
    item = projects(:pep).work_items.find_by(number: 77)
    assert_equal "PEP-77", item.reference, "the Jira number carries across so existing links survive"
    assert_equal "bug", item.kind
    assert_equal "urgent", item.priority, "Jira 'Highest' is our 'urgent'"
    assert_equal "In progress", item.workflow_state.name
    assert_equal 5.0, item.estimate, "Jira stores seconds; we hold hours"
    assert_equal 1, item.work_comments.count
  end

  test "a dry run reports without writing" do
    result = Imports::Jira.call(payload: jira_export, project: projects(:pep),
                                actor: users(:admin), dry_run: true)

    assert_equal 1, result.created["issues"], "it says what it would do"
    assert_nil projects(:pep).work_items.find_by(number: 77), "and writes nothing"
  end

  test "an unknown status is REPORTED, never guessed" do
    payload = jira_export("status" => { "name" => "Awaiting Vendor" })
    result = Imports::Jira.call(payload: payload, project: projects(:pep), actor: users(:admin))

    assert_includes result.to_h[:unmapped]["status"], "Awaiting Vendor"
    item = projects(:pep).work_items.find_by(number: 77)
    assert_equal projects(:pep).default_state, item.workflow_state, "falls back, and says so"
  end

  test "re-running updates rather than duplicating" do
    Imports::Jira.call(payload: jira_export, project: projects(:pep), actor: users(:admin))
    second = Imports::Jira.call(payload: jira_export("summary" => "Renamed upstream"),
                                project: projects(:pep), actor: users(:admin))

    assert_equal 1, second.updated["issues"]
    assert_equal 1, projects(:pep).work_items.where(number: 77).count, "a failed migration can just be re-run"
    assert_equal "Renamed upstream", projects(:pep).work_items.find_by(number: 77).title
  end

  test "Atlassian Document Format descriptions come across as text" do
    adf = { "type" => "doc", "content" => [ { "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "Hello from ADF" } ] } ] }
    Imports::Jira.call(payload: jira_export("description" => adf),
                       project: projects(:pep), actor: users(:admin))

    assert_match "Hello from ADF", projects(:pep).work_items.find_by(number: 77).description
    refute_match "\"type\"", projects(:pep).work_items.find_by(number: 77).description,
                 "not raw JSON dumped into the description"
  end

  # ── Freshdesk → cases ─────────────────────────────────────────────────────
  def freshdesk_export
    {
      "companies" => [ { "id" => 9, "name" => "Northwind Ltd" } ],
      "contacts" => [ { "id" => 5, "name" => "Ravi Kumar", "email" => "ravi@northwind.test", "company_id" => 9 } ],
      "tickets" => [ {
        "id" => 4321, "requester_id" => 5, "subject" => "Invoice not received",
        "description_text" => "We never got the March invoice.",
        "status" => 3, "priority" => 3, "source" => 1,
        "conversations" => [ { "body_text" => "Checking with billing.", "private" => true } ]
      } ]
    }
  end

  test "a Freshdesk ticket becomes a case with its contact and organisation" do
    result = Imports::Freshdesk.call(payload: freshdesk_export)

    assert_equal 1, result.created["cases"]
    kase = Case.find_by(external_id: "freshdesk:4321")
    assert_equal "Invoice not received", kase.subject
    assert_equal "in_progress", kase.status
    assert_equal "high", kase.priority
    assert_equal "ravi@northwind.test", kase.contact.email
    assert_equal "Northwind Ltd", kase.contact.organisation.name
    assert_equal 1, kase.messages.count
    assert kase.messages.first.kind_internal_note?, "a private Freshdesk note stays internal"
  end

  test "Freshdesk re-runs are idempotent on the ticket id" do
    Imports::Freshdesk.call(payload: freshdesk_export)
    assert_difference "Case.count", 0 do
      Imports::Freshdesk.call(payload: freshdesk_export)
    end
  end

  test "an unknown Freshdesk status is reported" do
    payload = freshdesk_export
    payload["tickets"][0]["status"] = 42
    result = Imports::Freshdesk.call(payload: payload)

    assert_includes result.to_h[:unmapped]["status"], "42"
  end

  # ── KanZen → project ──────────────────────────────────────────────────────
  test "a KanZen board becomes a project with its columns and cards" do
    board = { "title" => "Launch Plan", "columns" => [
      { "title" => "Ideas", "cards" => [ { "title" => "Write the brief" } ] },
      { "title" => "Doing", "wipLimit" => 3, "cards" => [ { "title" => "Draft copy",
        "checklist" => [ { "text" => "Headline" } ], "comments" => [ { "text" => "Keep it short" } ] } ] },
      { "title" => "Shipped", "cards" => [] }
    ] }
    result = Imports::Kanzen.call(payload: board, key: "LAUNCH", actor: users(:admin))

    project = Project.find_by(key: "LAUNCH")
    assert_equal "Launch Plan", project.name
    assert_equal %w[Ideas Doing Shipped], project.workflow_states.ordered.map(&:name)
    assert project.workflow_states.ordered.last.category_done?, "the last column is where work finishes"
    assert_equal 3, project.workflow_states.ordered.second.wip_limit, "KanZen's WIP limit carries over"
    assert_equal 2, result.created["cards"]
    assert_equal 1, result.created["checklist_items"]

    draft = project.work_items.find_by(title: "Draft copy")
    assert_equal 1, draft.children.count, "checklist entries become child items"
    assert_equal 1, draft.work_comments.count
  end

  test "a malformed export reports an error instead of raising" do
    result = Imports::Kanzen.call(payload: "{not json", actor: users(:admin))
    assert result.errors.any?
    assert_match(/could not parse/, result.errors.first)
  end

  # ── Regressions from the 2026-07-28 adversarial review ────────────────────
  test "issues from different Jira projects do not collapse onto one item" do
    payload = { "issues" => [
      { "key" => "AAA-1", "fields" => { "summary" => "from AAA", "status" => { "name" => "To Do" } } },
      { "key" => "BBB-1", "fields" => { "summary" => "from BBB", "status" => { "name" => "To Do" } } },
      { "key" => "CCC-1", "fields" => { "summary" => "from CCC", "status" => { "name" => "To Do" } } }
    ] }
    before = projects(:pep).work_items.find_by(number: 1).title

    result = Imports::Jira.call(payload: payload, project: projects(:pep), actor: users(:admin))

    assert_equal 3, result.created["issues"], "three distinct issues are three items"
    assert_equal before, projects(:pep).work_items.find_by(number: 1).reload.title,
                 "a pre-existing item must never be overwritten by an import"
    %w[AAA-1 BBB-1 CCC-1].each do |key|
      assert projects(:pep).work_items.exists?(source_key: key), "#{key} was lost"
    end
  end

  test "an import never writes into a soft-deleted row" do
    Imports::Jira.call(payload: jira_export, project: projects(:pep), actor: users(:admin))
    projects(:pep).work_items.find_by(source_key: "PEP-77").destroy

    result = Imports::Jira.call(payload: jira_export("summary" => "second run"),
                                project: projects(:pep), actor: users(:admin))

    assert_equal 1, result.created["issues"], "a tombstone is not an existing row to update"
    assert projects(:pep).work_items.exists?(title: "second run"), "the re-import must be visible"
  end

  test "a malformed key reports an error instead of aborting the whole import" do
    payload = { "issues" => [
      { "key" => "GOOD-1", "fields" => { "summary" => "keep me" } },
      { "key" => "1BAD-2", "fields" => { "summary" => "bad key" } },
      { "key" => "GOOD-2", "fields" => { "summary" => "keep me too" } }
    ] }

    result = nil
    assert_nothing_raised { result = Imports::Jira.call(payload: payload, actor: users(:admin)) }
    assert result.errors.any?, "the bad row must be reported"
    assert_equal 2, result.created["issues"], "one bad row must not lose the good ones"
  end

  test "a Jira key with no number still imports and stays idempotent" do
    payload = { "issues" => [ { "key" => "NONUM", "fields" => { "summary" => "keyless" } } ] }
    Imports::Jira.call(payload: payload, project: projects(:pep), actor: users(:admin))
    second = Imports::Jira.call(payload: payload, project: projects(:pep), actor: users(:admin))

    assert_equal 1, second.updated["issues"], "re-running must not duplicate"
    assert_equal 1, projects(:pep).work_items.where(source_key: "NONUM").count
  end
end
