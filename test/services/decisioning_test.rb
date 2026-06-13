require "test_helper"

# The rule-based decisioning layer: each rule computes a signal over the
# deployment's own data and emits a proposed Decision carrying its
# accountability tier. Rules never act — they recommend. Fixtures populate
# leads/cases/deals, so assertions target specific subjects.
class DecisioningTest < ActiveSupport::TestCase
  def decisions_for(rule_class)
    rule_class.new.evaluate
  end

  def decision_for(decisions, subject)
    decisions.find { |d| d.subject_type == subject.class.name && d.subject_id == subject.id }
  end

  # --- LeadScore (autonomous) ---

  test "lead_score flags a high-value open lead and skips a thin one" do
    hot = Lead.create!(name: "Hot", email: "hot@x.com", phone: "+91990000001",
                       company_name: "Acme", source: :referral, status: :new)
    thin = Lead.create!(name: "Thin", email: "thin@x.com", source: :manual, status: :new) # email only → score 1

    decisions = decisions_for(Decisioning::Rules::LeadScore)
    hit = decision_for(decisions, hot)
    assert hit, "expected a decision for the high-value lead"
    assert_equal :autonomous, hit.decision_class
    assert_equal "high_value_lead", hit.signal
    assert_includes hit.reasoning, "email"
    assert_nil decision_for(decisions, thin)
  end

  test "lead_score ignores converted/closed leads" do
    won = Lead.create!(name: "Done", email: "d@x.com", phone: "+91990000002",
                       company_name: "Acme", source: :referral, status: :qualified)
    assert_nil decision_for(decisions_for(Decisioning::Rules::LeadScore), won)
  end

  # --- SlaAtRisk (confirm) ---

  test "sla_at_risk flags an imminent, not-breached case but not a far-off or overdue one" do
    risk = Case.create!(subject: "Due soon", contact: contacts(:asha))
    risk.update_columns(status: Case.statuses["in_progress"], resolution_breached: false,
                        resolution_due_at: 2.hours.from_now)
    far = Case.create!(subject: "Plenty of time", contact: contacts(:asha))
    far.update_columns(status: Case.statuses["in_progress"], resolution_breached: false,
                       resolution_due_at: 2.days.from_now)
    overdue = Case.create!(subject: "Already late", contact: contacts(:asha))
    overdue.update_columns(status: Case.statuses["in_progress"], resolution_breached: false,
                           resolution_due_at: 1.hour.ago)

    decisions = decisions_for(Decisioning::Rules::SlaAtRisk)
    hit = decision_for(decisions, risk)
    assert hit
    assert_equal :confirm, hit.decision_class
    assert_equal :write, hit.effect
    assert_nil decision_for(decisions, far)
    assert_nil decision_for(decisions, overdue)
  end

  # --- StalledDeal (autonomous) ---

  test "stalled_deal flags an open deal past the dwell threshold but not a fresh one" do
    pipeline = Pipeline.new(name: "Decisioning Funnel")
    pipeline.pipeline_stages.build([ { name: "New", position: 0, probability: 10 } ])
    pipeline.save!
    stage = pipeline.pipeline_stages.first

    stalled = nil
    travel_to(20.days.ago) { stalled = Deal.create!(name: "Old deal", pipeline: pipeline, pipeline_stage: stage, value: 1000) }
    fresh = Deal.create!(name: "New deal", pipeline: pipeline, pipeline_stage: stage, value: 1000)

    decisions = decisions_for(Decisioning::Rules::StalledDeal)
    hit = decision_for(decisions, stalled)
    assert hit
    assert_equal :autonomous, hit.decision_class
    assert_match(/stalled \d+ days/, hit.recommendation)
    assert_nil decision_for(decisions, fresh)
  end

  # --- Engine ---

  test "the engine aggregates all rules and summarises by decision class" do
    Lead.create!(name: "Hot", email: "h@x.com", phone: "+91990000003",
                 company_name: "Acme", source: :referral, status: :new)
    risk = Case.create!(subject: "Due soon", contact: contacts(:asha))
    risk.update_columns(status: Case.statuses["in_progress"], resolution_breached: false,
                        resolution_due_at: 2.hours.from_now)

    decisions = Decisioning::Engine.run
    assert(decisions.any? { |d| d.rule == "lead_score" })
    assert(decisions.any? { |d| d.rule == "sla_at_risk" })

    summary = Decisioning::Engine.summary(decisions)
    assert_operator summary[:autonomous], :>=, 1
    assert_operator summary[:confirm], :>=, 1
  end

  test "a decision carries versioned provenance" do
    Lead.create!(name: "Hot", email: "h2@x.com", phone: "+91990000004",
                 company_name: "Acme", source: :referral, status: :new)
    decision = decisions_for(Decisioning::Rules::LeadScore).first
    assert_match(/\Alead_score@1 Lead#\d+\z/, decision.provenance)
    assert decision.autonomous?
    assert_not decision.requires_human?
  end
end
