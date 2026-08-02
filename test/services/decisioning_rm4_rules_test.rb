require "test_helper"

class DecisioningRm4RulesTest < ActiveSupport::TestCase
  def proposal_for(rule_class, subject)
    rule_class.new.evaluate.find do |proposal|
      proposal.subject_type == subject.class.name && proposal.subject_id == subject.id
    end
  end

  def apply_proposal(proposal)
    decision = Decisioning::Dispatcher.persist([ proposal ]).first
    Decisioning::Dispatcher.apply!(decision)
    decision
  end

  test "routing suggestion parks the first matching intake rule until approval" do
    kase = Imports::Mode.run do
      Case.create!(subject: "Route imported pension case", priority: :high, contact: contacts(:asha))
    end
    rule = RoutingRule.create!(name: "High priority pension", if_priority: :high,
                               then_queue: queues(:pensions), then_priority: :urgent)

    proposal = proposal_for(Decisioning::Rules::RoutingSuggestion, kase)
    assert proposal
    assert_equal :confirm, proposal.decision_class
    assert_equal "apply_routing_rule", proposal.action
    assert_equal rule.id, proposal.action_params["routing_rule_id"]

    decision = Decisioning::Dispatcher.persist([ proposal ]).first
    assert_nil kase.reload.routed_by_rule_id
    Decisioning::Dispatcher.approve!(decision, approver: users(:decision_reviewer))
    assert_equal rule, kase.reload.routed_by_rule
    assert_equal queues(:pensions), kase.queue
    assert_equal "urgent", kase.priority
  end

  test "routing approval fails closed when the rule no longer matches" do
    kase = Imports::Mode.run do
      Case.create!(subject: "Imported urgent matter", priority: :high, contact: contacts(:asha))
    end
    RoutingRule.create!(name: "High only", if_priority: :high, then_queue: queues(:pensions))
    decision = Decisioning::Dispatcher.persist([
      proposal_for(Decisioning::Rules::RoutingSuggestion, kase)
    ]).first
    kase.update!(priority: :low)

    assert_raises(Decisioning::Error) do
      Decisioning::Dispatcher.approve!(decision, approver: users(:decision_reviewer))
    end
    assert decision.reload.status_proposed?
    assert_nil kase.reload.routed_by_rule_id
  end

  test "recent low CSAT adds a reversible churn-risk label" do
    contact = Contact.create!(name: "Low CSAT", email: "low-csat@example.test")
    kase = Case.create!(subject: "Poor experience", contact: contact)
    CsatSurvey.create!(case: kase, contact: contact, invited_at: 2.days.ago,
                       responded_at: 1.day.ago, score: 2)

    proposal = proposal_for(Decisioning::Rules::ChurnRisk, contact)
    assert proposal
    assert_equal "churn_risk", proposal.signal
    assert_equal :autonomous, proposal.decision_class
    apply_proposal(proposal)
    assert contact.reload.label?("churn_risk")
  end

  test "an open breached case marks its contact at risk" do
    contact = Contact.create!(name: "Breached", email: "breached@example.test")
    kase = Case.create!(subject: "Overdue", contact: contact)
    kase.update_columns(status: Case.statuses.fetch("in_progress"), resolution_breached: true)

    proposal = proposal_for(Decisioning::Rules::AtRiskContact, contact)
    assert proposal
    assert_includes proposal.reasoning, "1 open resolution-breached case"
    apply_proposal(proposal)
    assert contact.reload.label?("at_risk_contact")
  end

  test "active direct or organisation SLA coverage marks a priority contact" do
    direct = Contact.create!(name: "Direct VIP", email: "direct-vip@example.test")
    Entitlement.create!(name: "Direct decisioning coverage", contact: direct,
                        sla_policy: sla_policies(:standard), starts_at: 1.day.ago)
    organisation_contact = Contact.create!(name: "Org VIP", email: "org-vip@example.test",
                                           organisation: organisations(:branch))
    Entitlement.create!(name: "Organisation decisioning coverage", organisation: organisations(:branch),
                        sla_policy: sla_policies(:standard), starts_at: 1.day.ago)

    proposals = Decisioning::Rules::VipContact.new.evaluate
    assert proposal_for(Decisioning::Rules::VipContact, direct)
    assert proposals.any? { |proposal| proposal.subject_id == organisation_contact.id }
  end

  test "expired SLA coverage does not mark a contact as priority" do
    contact = Contact.create!(name: "Expired", email: "expired-vip@example.test")
    Entitlement.create!(name: "Expired decisioning coverage", contact: contact,
                        sla_policy: sla_policies(:standard), starts_at: 10.days.ago, ends_at: 1.day.ago)

    assert_nil proposal_for(Decisioning::Rules::VipContact, contact)
  end
end
