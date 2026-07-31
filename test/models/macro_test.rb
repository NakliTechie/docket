require "test_helper"

class MacroTest < ActiveSupport::TestCase
  test "interpolates case and agent variables" do
    macro = Macro.create!(name: "Greeting",
      body: "Dear {{contact_name}}, your case {{tracking_id}} is with {{agent_name}} ({{queue_name}}).")
    rendered = macro.render_for(cases(:pension_case), agent: users(:agent_a))
    assert_equal "Dear Asha Rao, your case DKT-TEST-2345 is with Asha Agent (Pensions).", rendered
  end

  test "unknown variables pass through untouched" do
    macro = Macro.create!(name: "Odd", body: "Hello {{unknown_thing}}")
    assert_equal "Hello {{unknown_thing}}", macro.render_for(cases(:pension_case))
  end

  test "missing values render empty" do
    macro = Macro.create!(name: "NoAgent", body: "Agent: {{agent_name}}.")
    assert_equal "Agent: .", macro.render_for(cases(:pension_case), agent: nil)
  end

  test "action fields apply through the case state machine" do
    macro = Macro.create!(name: "Triage", body: "Taking ownership",
                          message_kind: "internal_note", set_status: "in_progress",
                          set_priority: "urgent", set_queue: queues(:sanitation),
                          set_assignee: users(:agent_a))
    kase = cases(:pension_case)
    assert macro.apply_to!(kase, requested_by: users(:admin))
    kase.reload
    assert_equal "in_progress", kase.status
    assert_equal "urgent", kase.priority
    assert_equal queues(:sanitation), kase.queue
    assert_equal users(:agent_a), kase.assignee
  end
end
