require "test_helper"

# Deterministic routing on intake (rules win; AI is the fallback). Llm is off in
# the test env, so a matched rule completes triage itself (→ :triaged).
class CaseRoutingTest < ActiveSupport::TestCase
  def make_case(**overrides)
    Case.create!({ subject: "ATM ate my card", channel: :web_portal, priority: :high,
                   contact: contacts(:asha) }.merge(overrides))
  end

  test "a matching rule routes the case, assigns provenance, and completes triage" do
    RoutingRule.create!(name: "ATM→pensions", if_subject_contains: "atm",
                        then_queue: queues(:pensions), then_priority: "urgent")
    kase = make_case.reload
    assert_equal queues(:pensions), kase.queue
    assert_equal "urgent", kase.priority
    assert kase.routed_by_rule_id.present?
    assert kase.status_triaged?, "Llm off → the rule completes triage"
  end

  test "no matching rule is a no-op" do
    kase = make_case(subject: "completely unrelated").reload
    assert_nil kase.routed_by_rule_id
    assert kase.queue.nil? || kase.queue == CaseQueue.default
  end

  test "the first matching active rule wins; inactive rules are skipped" do
    RoutingRule.create!(name: "off", position: 0, active: false, if_priority: "high", then_queue: queues(:sanitation))
    RoutingRule.create!(name: "first", position: 1, if_priority: "high", then_queue: queues(:pensions))
    RoutingRule.create!(name: "second", position: 2, if_priority: "high", then_queue: queues(:sanitation))
    assert_equal queues(:pensions), make_case.reload.queue
  end

  test "specific_user assignment assigns the named active user" do
    RoutingRule.create!(name: "to asha", if_priority: "high", then_queue: queues(:pensions),
                        then_assignment: :specific_user, then_assignee: users(:agent_a))
    assert_equal users(:agent_a), make_case.reload.assignee
  end

  test "least_loaded assignment picks the queue member with fewest open cases" do
    queue = queues(:pensions)
    QueueMembership.find_or_create_by!(queue: queue, user: users(:agent_a))
    QueueMembership.find_or_create_by!(queue: queue, user: users(:agent_b))
    # agent_a already carries an open case → least-loaded should pick agent_b.
    Case.create!(subject: "load", channel: :staff, contact: contacts(:asha),
                 queue: queue, assignee: users(:agent_a))
    RoutingRule.create!(name: "balance", if_priority: "high", then_queue: queue, then_assignment: :least_loaded)
    assert_equal users(:agent_b), make_case.reload.assignee
  end

  test "round_robin assignment rotates across active members" do
    queue = queues(:sanitation)
    QueueMembership.where(queue: queue).delete_all
    QueueMembership.create!(queue: queue, user: users(:agent_a))
    QueueMembership.create!(queue: queue, user: users(:agent_b))
    RoutingRule.create!(name: "rr", if_subject_contains: "rota", then_queue: queue, then_assignment: :round_robin)
    a = make_case(subject: "rota one").reload
    b = make_case(subject: "rota two").reload
    assert_not_equal a.assignee_id, b.assignee_id, "consecutive cases rotate to different members"
  end

  test "CaseAgent skips re-classification for a rule-routed case" do
    RoutingRule.create!(name: "kw", if_subject_contains: "atm", then_queue: queues(:pensions))
    kase = make_case
    kase.update_columns(status: Case.statuses["new"]) # pretend AI is about to run
    result = CaseAgent.new(kase, client: Object.new).send(:route)
    assert_equal "rule", result["routed_by"]
    assert kase.reload.status_triaged?
  end
end
