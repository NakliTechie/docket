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

  test "Jira explicitly maps typed custom fields and reports the rest" do
    CustomFieldDefinition.create!(resource_type: "work_items", key: "story_points",
                                  label: "Story points", field_type: :integer)
    payload = jira_export("customfield_10010" => "8", "customfield_99999" => "unmapped")
    result = Imports::Jira.call(payload: payload, project: projects(:pep), actor: users(:admin),
                                custom_field_map: { story_points: "customfield_10010" })

    item = projects(:pep).work_items.find_by!(source_key: "PEP-77")
    assert_equal 8, item.custom_fields.fetch("story_points")
    assert_includes result.serialized_unmapped["dropped.issue.fields"], "customfield_99999"
    refute_includes result.serialized_unmapped["dropped.issue.fields"], "customfield_10010"
  end

  test "Jira reports invalid custom-field coercions in the returned result" do
    CustomFieldDefinition.create!(resource_type: "work_items", key: "story_points",
                                  label: "Story points", field_type: :integer)
    result = Imports::Jira.call(
      payload: jira_export("customfield_10010" => "not-a-number"),
      project: projects(:pep), actor: users(:admin),
      custom_field_map: { story_points: "customfield_10010" }
    )

    assert_includes result.serialized_unmapped["custom_field.story_points"], "not-a-number"
  end

  test "a dry run reports without writing" do
    result = Imports::Jira.call(payload: jira_export, project: projects(:pep),
                                actor: users(:admin), dry_run: true)

    assert_equal 1, result.created["issues"], "it says what it would do"
    assert_not WorkItem.exists?(project: projects(:pep), number: 77), "and writes nothing"
  end

  test "an unknown status is REPORTED, never guessed" do
    payload = jira_export("status" => { "name" => "Awaiting Vendor" })
    result = Imports::Jira.call(payload: payload, project: projects(:pep), actor: users(:admin))

    assert_includes result.to_h[:unmapped]["status"], "Awaiting Vendor"
    item = projects(:pep).work_items.find_by(number: 77)
    assert_nil item, "an unmapped state is not guessed into a live workflow column"
    assert result.errors.any?
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

  test "Freshdesk explicitly maps typed custom fields and reports the rest" do
    CustomFieldDefinition.create!(resource_type: "cases", key: "account_tier",
                                  label: "Account tier", field_type: :single_select,
                                  options: %w[Gold Silver])
    payload = freshdesk_export
    payload["tickets"][0]["custom_fields"] = { "cf_tier" => "Gold", "cf_legacy" => "keep visible" }
    result = Imports::Freshdesk.call(payload: payload,
                                     custom_field_map: { account_tier: "cf_tier" })

    assert_equal "Gold", Case.find_by!(external_id: "freshdesk:4321").custom_fields.fetch("account_tier")
    assert_includes result.serialized_unmapped["dropped.ticket.custom_fields"], "cf_legacy"
    refute_includes result.serialized_unmapped["dropped.ticket.custom_fields"], "cf_tier"
  end

  test "Freshdesk reports invalid custom-field coercions in the returned result" do
    CustomFieldDefinition.create!(resource_type: "cases", key: "account_tier",
                                  label: "Account tier", field_type: :single_select,
                                  options: %w[Gold Silver])
    payload = freshdesk_export
    payload["tickets"][0]["custom_fields"] = { "cf_tier" => "Bronze" }
    result = Imports::Freshdesk.call(
      payload: payload, custom_field_map: { account_tier: "cf_tier" }
    )

    assert_includes result.serialized_unmapped["custom_field.account_tier"], "Bronze"
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

  test "Freshdesk delta re-import applies a status change and a new conversation" do
    initial = freshdesk_export
    initial["tickets"][0].merge!("status" => 2, "conversations" => [
      { "id" => 1, "body_text" => "first", "private" => true, "incoming" => false }
    ])
    Imports::Freshdesk.call(payload: initial)

    delta = freshdesk_export
    delta["tickets"][0].merge!("status" => 5, "closed_at" => "2025-01-03T12:00:00Z",
                                "conversations" => [
      { "id" => 1, "body_text" => "first", "private" => true, "incoming" => false },
      { "id" => 2, "body_text" => "closing note", "private" => true, "incoming" => false }
    ])
    result = Imports::Freshdesk.call(payload: delta)

    kase = Case.find_by(external_id: "freshdesk:4321")
    assert kase.status_closed?, result.to_h.inspect
    assert_equal 2, kase.messages.count
    assert_equal Date.new(2025, 1, 3), kase.closed_at.to_date
  end

  test "Freshdesk sparse contact rows do not erase enriched local data" do
    payload = freshdesk_export
    payload["contacts"][0]["phone"] = "+919812345678"
    Imports::Freshdesk.call(payload: payload)
    contact = Contact.find_by(email: "ravi@northwind.test")

    Imports::Freshdesk.call(payload: { "contacts" => [
      { "id" => 5, "email" => "ravi@northwind.test" }
    ], "tickets" => [] })

    assert_equal "Ravi Kumar", contact.reload.name
    assert_equal "+919812345678", contact.phone
    assert_equal "Northwind Ltd", contact.organisation.name
  end

  test "Freshdesk does not overwrite a contact with a customer SSO identity" do
    protected_contact = Contact.create!(name: "Portal Ravi", email: "portal.ravi@example.test",
                                        external_id: "SSO-RAVI-1")
    result = Imports::Freshdesk.call(payload: {
      "contacts" => [ { "id" => 55, "name" => "Source Ravi",
                         "email" => protected_contact.email } ], "tickets" => []
    })

    assert_equal "Portal Ravi", protected_contact.reload.name
    assert_includes result.serialized_unmapped["protected_contact"], "55"
  end

  test "Freshdesk reconstructs first response and SLA dates from source history" do
    Setting.set("default_sla_policy_id", sla_policies(:standard).id)
    historic = freshdesk_export
    historic["tickets"][0].merge!(
      "created_at" => "2024-01-01T09:00:00Z", "status" => 4,
      "resolved_at" => "2024-01-20T09:00:00Z",
      "conversations" => [ {
        "id" => 99, "body_text" => "late staff response", "private" => false,
        "incoming" => false, "created_at" => "2024-01-16T09:00:00Z"
      } ]
    )

    Imports::Freshdesk.call(payload: historic)
    kase = Case.find_by(external_id: "freshdesk:4321")

    assert_equal Time.zone.parse("2024-01-16T09:00:00Z"), kase.first_responded_at
    assert_equal Time.zone.parse("2024-01-01T09:30:00Z"), kase.first_response_due_at
    assert kase.first_response_breached?
    assert_equal Time.zone.parse("2024-01-01T17:00:00Z"), kase.resolution_due_at
    assert kase.resolution_breached?
  ensure
    Setting.unset("default_sla_policy_id")
  end

  test "Jira uses the source resolution time for completed work" do
    payload = jira_export(
      "status" => { "name" => "Done" },
      "resolutiondate" => "2024-05-04T10:30:00Z",
      "created" => "2024-05-01T08:00:00Z"
    )
    Imports::Jira.call(payload: payload, project: projects(:pep), actor: users(:admin))

    item = projects(:pep).work_items.find_by(source_key: "PEP-77")
    assert_equal Time.zone.parse("2024-05-04T10:30:00Z"), item.closed_at
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

  test "KanZen source identities preserve duplicate titles and make re-runs idempotent" do
    board = { "id" => "BOARD-1", "title" => "Duplicate titles", "columns" => [
      { "id" => "todo", "title" => "Todo", "cards" => [ { "id" => "A", "title" => "Review" } ] },
      { "id" => "done", "title" => "Done", "cards" => [ { "id" => "B", "title" => "Review" } ] }
    ] }
    Imports::Kanzen.call(payload: board, key: "DUP", actor: users(:admin))
    second = Imports::Kanzen.call(payload: board, key: "DUP", actor: users(:admin))

    project = Project.find_by(key: "DUP")
    assert_equal 2, project.work_items.where(title: "Review").count
    assert_equal 2, second.updated["cards"]
    assert_equal 0, second.created["cards"]
  end

  # ── Regressions from the 2026-07-28 adversarial review ────────────────────
  test "issues from different Jira projects do not collapse onto one item" do
    payload = { "issues" => [
      { "key" => "AAA-1", "fields" => { "summary" => "from AAA", "status" => { "name" => "Backlog" } } },
      { "key" => "BBB-1", "fields" => { "summary" => "from BBB", "status" => { "name" => "Backlog" } } },
      { "key" => "CCC-1", "fields" => { "summary" => "from CCC", "status" => { "name" => "Backlog" } } }
    ] }
    before = projects(:pep).work_items.find_by(number: 1).title

    result = Imports::Jira.call(payload: payload, project: projects(:pep), actor: users(:admin))

    assert_equal 3, result.created["issues"], result.to_h.inspect
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

    assert_equal 1, result.created["issues"], result.to_h.inspect
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
