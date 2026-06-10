require "test_helper"

class CasePolicyTest < ActiveSupport::TestCase
  def policy_for(user, record)
    CasePolicy.new(user, record)
  end

  test "all staff can view cases" do
    %i[admin supervisor agent_a readonly].each do |role|
      assert policy_for(users(role), cases(:pension_case)).show?, "#{role} should see cases"
      assert policy_for(users(role), cases(:pension_case)).index?
    end
  end

  test "readonly cannot mutate anything" do
    policy = policy_for(users(:readonly), cases(:pension_case))
    refute policy.create?
    refute policy.update?
    refute policy.transition?
    refute policy.assign?
    refute policy.destroy?
  end

  test "agents work cases in their queues" do
    assert policy_for(users(:agent_a), cases(:pension_case)).update?
    assert policy_for(users(:agent_a), cases(:pension_case)).transition?
  end

  test "agents work cases assigned to them regardless of queue" do
    assert policy_for(users(:agent_a), cases(:assigned_case)).update?
  end

  test "agents work unassigned cases outside their queues" do
    assert policy_for(users(:agent_b), cases(:pension_case)).update?
  end

  test "agents cannot work cases assigned to others outside their queues" do
    refute policy_for(users(:agent_b), cases(:assigned_case)).update?
    refute policy_for(users(:agent_b), cases(:assigned_case)).transition?
  end

  test "agents cannot destroy cases" do
    refute policy_for(users(:agent_a), cases(:pension_case)).destroy?
  end

  test "supervisors and admins work and destroy any case" do
    %i[admin supervisor].each do |role|
      policy = policy_for(users(role), cases(:assigned_case))
      assert policy.update?
      assert policy.destroy?
    end
  end

  test "unauthenticated scope is empty" do
    assert_empty CasePolicy::Scope.new(nil, Case).resolve
  end

  test "staff scope sees all cases" do
    assert_equal Case.count, CasePolicy::Scope.new(users(:readonly), Case).resolve.count
  end
end
