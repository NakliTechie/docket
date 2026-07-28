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

  # M1 — six more Scopes were gated on "any signed-in user", not the read
  # permission their own index?/show? require. Every functional role holds
  # case:read, so the case-family change tightens only the unauthenticated path
  # today (plus any future role/token lacking it); pipeline:read is the real
  # tightening — customer_service and technical do not hold it.
  test "case-family scopes are gated on case:read" do
    assert_empty CasePolicy::Scope.new(nil, Case).resolve
    assert_empty CaseQueuePolicy::Scope.new(nil, CaseQueue).resolve
    assert_empty CategoryPolicy::Scope.new(nil, Category).resolve
    assert_empty MessagePolicy::Scope.new(nil, Message).resolve
    assert_includes CasePolicy::Scope.new(users(:customer_service), Case).resolve, cases(:pension_case)
    assert_includes CategoryPolicy::Scope.new(users(:technical), Category).resolve, categories(:pension_delay)
    assert_includes MessagePolicy::Scope.new(users(:customer_service), Message).resolve, messages(:note_on_pension)
  end

  test "pipeline and sequence scopes gate on pipeline:read, which support roles lack" do
    pipeline = pipelines(:sales)
    assert_includes PipelinePolicy::Scope.new(users(:sales), Pipeline).resolve, pipeline
    refute_includes PipelinePolicy::Scope.new(users(:customer_service), Pipeline).resolve, pipeline
    refute_includes PipelinePolicy::Scope.new(users(:technical), Pipeline).resolve, pipeline
    assert_empty PipelinePolicy::Scope.new(nil, Pipeline).resolve

    # bypass the no_steps validation — this test is about scoping, not validity
    seq = Sequence.new(name: "Welcome flow")
    seq.save!(validate: false)
    assert_includes SequencePolicy::Scope.new(users(:sales), Sequence).resolve, seq
    refute_includes SequencePolicy::Scope.new(users(:customer_service), Sequence).resolve, seq
    assert_empty SequencePolicy::Scope.new(nil, Sequence).resolve
  end
end
