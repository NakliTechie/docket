require "test_helper"

# An import RECONSTRUCTS history. It must not re-enact it.
#
# The Freshdesk importer created every non-private conversation as a
# public_reply, and `direction` defaults to :outbound — so importing a ticket
# with three replies sent three "Update on your case" emails to the real
# customer. A cutover for a customer with any history would mail their entire
# customer base. Same class of problem for AI triage, webhooks and sentiment:
# they are reactions to something happening NOW, and an import is not now.
class ImportSideEffectsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  def payload(conversations)
    {
      "contacts" => [ { "id" => 5, "name" => "Ravi", "email" => "ravi@customer.test" } ],
      "tickets" => [ {
        "id" => 900, "requester_id" => 5, "subject" => "Historic ticket",
        "description_text" => "opened long ago", "status" => 2, "priority" => 1,
        "source" => 1, "created_at" => "2024-03-01T09:00:00Z",
        "conversations" => conversations
      } ]
    }
  end

  test "importing a ticket with replies sends NO email to the customer" do
    conversations = [
      { "body_text" => "first reply", "private" => false },
      { "body_text" => "second reply", "private" => false },
      { "body_text" => "third reply", "private" => false }
    ]

    assert_no_enqueued_emails do
      Imports::Freshdesk.call(payload: payload(conversations))
    end
  end

  test "an import does not enqueue AI triage or publish webhooks" do
    WebhookEndpoint.create!(name: "hook", url: "https://example.test/h",
                            events: %w[case.created], active: true)

    assert_no_difference "WebhookDelivery.count" do
      assert_no_enqueued_jobs only: CaseAgentJob do
        Imports::Freshdesk.call(payload: payload([]))
      end
    end
  end

  test "imported history keeps its original dates" do
    Imports::Freshdesk.call(payload: payload([]))
    kase = Case.find_by(external_id: "freshdesk:900")

    assert_equal Date.new(2024, 3, 1), kase.created_at.to_date,
                 "stamping every case with the migration date destroys all backlog and trend history"
  end

  test "a customer's own reply is recorded as inbound, not as a staff reply" do
    Imports::Freshdesk.call(payload: payload([
      { "body_text" => "customer wrote this", "private" => false, "incoming" => true },
      { "body_text" => "agent wrote this", "private" => false, "incoming" => false }
    ]))
    kase = Case.find_by(external_id: "freshdesk:900")

    inbound = kase.messages.find_by(body: "customer wrote this")
    outbound = kase.messages.find_by(body: "agent wrote this")
    assert inbound.direction_inbound?, "the customer's own words must not become a staff reply"
    assert outbound.direction_outbound?
  end

  test "Jira history does not publish work webhooks" do
    WebhookEndpoint.create!(name: "work hook", url: "https://example.test/work",
                            events: %w[work_item.created work_item.commented], active: true)
    payload = { "issues" => [ {
      "key" => "PEP-700", "fields" => {
        "summary" => "Historic work", "status" => { "name" => "Backlog" },
        "comment" => { "comments" => [ { "id" => "C-1", "body" => "Old note" } ] }
      }
    } ] }

    assert_no_difference "WebhookDelivery.count" do
      Imports::Jira.call(payload: payload, project: projects(:pep), actor: users(:admin))
    end
  end

  test "an imported customer reply does not reopen a closed case" do
    historic = payload([
      { "id" => 22, "body_text" => "historic customer follow-up", "private" => false,
        "incoming" => true, "created_at" => "2024-03-03T09:00:00Z" }
    ])
    historic["tickets"][0].merge!("status" => 5, "closed_at" => "2024-03-02T09:00:00Z")

    Imports::Freshdesk.call(payload: historic)

    assert Case.find_by(external_id: "freshdesk:900").status_closed?
  end
end
