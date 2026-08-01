require "test_helper"

class LeadRoutingRuleTest < ActiveSupport::TestCase
  def lead(**attrs)
    Lead.new({ name: "Acme buyer", email: "buyer@acme.example", company_name: "Acme Corp",
               source: :web_form }.merge(attrs))
  end

  test "name is required" do
    refute LeadRoutingRule.new(then_assignment: :round_robin).valid?
  end

  test "specific_user requires an owner" do
    rule = LeadRoutingRule.new(name: "R", then_assignment: :specific_user)
    refute rule.valid?
    assert rule.errors[:then_owner_id].present?
  end

  test "a rule with no conditions is a valid catch-all matching every lead" do
    rule = LeadRoutingRule.new(name: "Catch-all", then_assignment: :round_robin)
    assert rule.valid?
    assert rule.matches?(lead)
  end

  test "matches on source" do
    rule = LeadRoutingRule.new(name: "Web only", if_source: "web_form")
    assert rule.matches?(lead(source: :web_form))
    refute rule.matches?(lead(source: :referral))
  end

  test "matches on company substring (case-insensitive)" do
    rule = LeadRoutingRule.new(name: "Acme", if_company_contains: "acme")
    assert rule.matches?(lead(company_name: "ACME Industries"))
    refute rule.matches?(lead(company_name: "Globex"))
  end

  test "matches on email domain, normalized (strips @, downcases)" do
    rule = LeadRoutingRule.new(name: "Acme domain", if_email_domain: "@ACME.example")
    assert_equal "acme.example", rule.if_email_domain
    assert rule.matches?(lead(email: "x@acme.example"))
    refute rule.matches?(lead(email: "x@globex.example"))
  end

  test "ALL set conditions must hold" do
    rule = LeadRoutingRule.new(name: "Both", if_source: "web_form", if_company_contains: "acme")
    assert rule.matches?(lead(source: :web_form, company_name: "Acme"))
    refute rule.matches?(lead(source: :web_form, company_name: "Globex"))
  end

  test "if_source must be a real Lead source" do
    refute LeadRoutingRule.new(name: "R", if_source: "carrier_pigeon").valid?
  end
end
