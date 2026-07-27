require "test_helper"

# After a migration, the identifiers people already hold — a ticket number in a
# customer's inbox, a Jira key in a commit message — must still resolve. They
# were being STORED and never READ.
class MigrationContinuityTest < ActiveSupport::TestCase
  test "a case is findable by the id it had in the old system" do
    kase = cases(:pension_case)
    kase.update!(external_id: "freshdesk:44821")

    assert_includes Case.search("44821"), kase,
                    "agents will paste the old ticket id on day one"
    assert_includes Case.search("freshdesk:44821"), kase
  end

  test "a work item is findable by title and by its old Jira key" do
    item = work_items(:pep_one)
    item.update!(source_key: "LEGACY-991")

    assert_includes WorkItem.search("LEGACY-991"), item
    assert_includes WorkItem.search(item.title.split.first), item
    assert_empty WorkItem.search("nothing-matches-this")
  end

  test "search is blank-safe and does not leak across tenants" do
    assert_equal Case.count, Case.search("").count
    assert_equal WorkItem.count, WorkItem.search(nil).count

    ActsAsTenant.with_tenant(tenants(:acme)) do
      assert_empty WorkItem.search(work_items(:pep_one).title)
    end
  end

  test "an unmapped Freshdesk status resolves from the ticket's own resolution data" do
    payload = {
      "contacts" => [ { "id" => 1, "name" => "R", "email" => "r@x.test" } ],
      "tickets" => [
        { "id" => 1, "requester_id" => 1, "subject" => "custom-closed", "status" => 12,
          "closed_at" => "2024-05-01T10:00:00Z", "priority" => 1, "source" => 1 },
        { "id" => 2, "requester_id" => 1, "subject" => "custom-open", "status" => 13,
          "priority" => 1, "source" => 1 }
      ]
    }
    result = Imports::Freshdesk.call(payload: payload)

    assert Case.find_by(external_id: "freshdesk:1").status_closed?,
           "a closed archive must not import as an open backlog"
    assert Case.find_by(external_id: "freshdesk:2").status_new?
    assert_includes result.to_h[:unmapped]["status"], "12", "and it still reports what it could not map"
  end
end
