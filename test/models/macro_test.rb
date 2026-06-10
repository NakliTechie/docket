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
end
