require "test_helper"

class DealContactRoleTest < ActiveSupport::TestCase
  setup do
    @deal = Deal.create!(name: "D", pipeline: pipelines(:sales), contact: contacts(:asha), owner: users(:sales))
  end

  test "a contact has one role per deal (unique)" do
    role = @deal.deal_contact_roles.create!(contact: contacts(:asha), role: :champion)
    assert role.role_champion?
    refute @deal.deal_contact_roles.build(contact: contacts(:asha), role: :influencer).valid?
  end

  test "human_role renders the localized label" do
    assert_equal "Decision maker",
                 @deal.deal_contact_roles.create!(contact: contacts(:asha), role: :decision_maker).human_role
  end
end
