require "test_helper"

# H2 (forward pass) — collection policy Scopes must gate on the read permission,
# not merely "any signed-in user". A role without lead:read/deal:read must not
# be able to list the CRM pipeline via index (which authorizes only by scope).
class ScopeAuthorizationTest < ActiveSupport::TestCase
  test "LeadPolicy::Scope is gated on lead:read" do
    lead = Lead.create!(name: "Scoped lead", email: "scoped-lead@t.test")
    assert_includes LeadPolicy::Scope.new(users(:sales), Lead).resolve, lead, "sales holds lead:read"
    refute_includes LeadPolicy::Scope.new(users(:customer_service), Lead).resolve, lead, "customer_service lacks lead:read"
    refute_includes LeadPolicy::Scope.new(users(:technical), Lead).resolve, lead, "technical lacks lead:read"
    assert_empty LeadPolicy::Scope.new(nil, Lead).resolve
  end

  test "DealPolicy::Scope is gated on deal:read" do
    deal = Deal.create!(name: "Scoped deal", pipeline: pipelines(:sales), pipeline_stage: pipeline_stages(:sales_new))
    assert_includes DealPolicy::Scope.new(users(:sales), Deal).resolve, deal
    refute_includes DealPolicy::Scope.new(users(:customer_service), Deal).resolve, deal
    refute_includes DealPolicy::Scope.new(users(:technical), Deal).resolve, deal
  end

  test "contact/macro/sla scopes deny a user without the read permission" do
    assert_empty ContactPolicy::Scope.new(nil, Contact).resolve
    assert_empty OrganisationPolicy::Scope.new(nil, Organisation).resolve
    assert_empty MacroPolicy::Scope.new(nil, Macro).resolve
    assert_empty SlaPolicyPolicy::Scope.new(nil, SlaPolicy).resolve
    # a holder of the read permission still sees the rows
    assert_includes SlaPolicyPolicy::Scope.new(users(:customer_service), SlaPolicy).resolve, sla_policies(:standard)
  end
end
