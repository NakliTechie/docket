require "test_helper"

# Shared expectations for the admin/supervisor-managed config resources
# and the staff-wide contact/organisation resources.
class ResourcePoliciesTest < ActiveSupport::TestCase
  test "queues categories and sla policies are managed by admin and supervisor only" do
    [ [ CaseQueuePolicy, queues(:pensions) ],
      [ CategoryPolicy, categories(:pension_delay) ],
      [ SlaPolicyPolicy, sla_policies(:standard) ] ].each do |policy_class, record|
      %i[admin supervisor].each do |role|
        policy = policy_class.new(users(role), record)
        assert policy.create?, "#{role} should create #{policy_class}"
        assert policy.update?
        assert policy.destroy?
      end
      %i[agent_a readonly].each do |role|
        policy = policy_class.new(users(role), record)
        assert policy.index?, "#{role} should list #{policy_class}"
        refute policy.create?, "#{role} should not create #{policy_class}"
        refute policy.update?
        refute policy.destroy?
      end
    end
  end

  test "contacts and organisations are workable by working staff" do
    [ [ ContactPolicy, contacts(:asha) ],
      [ OrganisationPolicy, organisations(:dpg) ] ].each do |policy_class, record|
      %i[admin supervisor agent_a].each do |role|
        policy = policy_class.new(users(role), record)
        assert policy.create?
        assert policy.update?
      end
      readonly_policy = policy_class.new(users(:readonly), record)
      assert readonly_policy.show?
      refute readonly_policy.create?
      refute readonly_policy.update?
      refute policy_class.new(users(:agent_a), record).destroy?
    end
  end

  test "message creation follows case workability" do
    message = Message.new(case: cases(:assigned_case))
    assert MessagePolicy.new(users(:agent_a), message).create?
    refute MessagePolicy.new(users(:agent_b), message).create?
    refute MessagePolicy.new(users(:readonly), message).create?
  end
end
