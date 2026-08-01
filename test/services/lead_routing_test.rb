require "test_helper"

class LeadRoutingTest < ActiveSupport::TestCase
  # Eligible lead owners = active users with lead:write.
  def eligible_owner?(user)
    user.present? && user.active? && user.can?("lead:write")
  end

  def new_lead(**attrs)
    Lead.create!({ name: "Acme buyer", email: "buyer@acme.example",
                   company_name: "Acme Corp", source: :web_form }.merge(attrs))
  end

  test "apply is a no-op when no rule matches" do
    lead = new_lead
    assert_nil lead.owner, "no rules configured → lead stays unowned"
  end

  test "the after_create hook routes a console/API lead through one seam" do
    LeadRoutingRule.create!(name: "Catch-all", then_assignment: :round_robin)
    lead = new_lead
    assert lead.owner.present?, "a matching rule assigned an owner on create"
    assert eligible_owner?(lead.owner)
  end

  test "specific_user assigns exactly that owner" do
    LeadRoutingRule.create!(name: "To sales", then_assignment: :specific_user, then_owner: users(:sales))
    assert_equal users(:sales), new_lead.owner
  end

  test "least_loaded picks an eligible owner with the fewest open leads" do
    # Pile open leads onto sales so a different eligible owner is lighter.
    3.times { Lead.create!(name: "x", email: "a#{_1}@x.example", owner: users(:sales), source: :manual) }
    LeadRoutingRule.create!(name: "Balance", then_assignment: :least_loaded)
    chosen = new_lead.owner
    assert eligible_owner?(chosen)
    assert_operator Lead.open_leads.where(owner_id: chosen.id).count, :<=,
                    Lead.open_leads.where(owner_id: users(:sales).id).count
  end

  test "import-sourced leads are NOT auto-routed (they carry their own ownership)" do
    LeadRoutingRule.create!(name: "Catch-all", then_assignment: :round_robin)
    assert_nil new_lead(source: :import).owner
  end

  test "a lead created with an owner already set is not overridden" do
    LeadRoutingRule.create!(name: "Catch-all", then_assignment: :round_robin)
    assert_equal users(:admin), new_lead(owner: users(:admin)).owner
  end

  test "first matching rule in position order wins" do
    LeadRoutingRule.create!(name: "Specific", position: 0, if_source: "web_form",
                            then_assignment: :specific_user, then_owner: users(:sales))
    LeadRoutingRule.create!(name: "Catch-all", position: 1, then_assignment: :specific_user,
                            then_owner: users(:client_admin))
    assert_equal users(:sales), new_lead(source: :web_form).owner
  end

  test "a matched rule with an empty eligible pool leaves the lead unowned (no crash)" do
    # specific_user pointing at an ineligible (readonly) user → no assignment.
    LeadRoutingRule.create!(name: "To readonly", then_assignment: :specific_user, then_owner: users(:readonly))
    assert_nil new_lead.owner
  end
end
