require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  test "only admins manage users" do
    assert UserPolicy.new(users(:admin), users(:agent_a)).update?
    %i[supervisor agent_a readonly].each do |role|
      refute UserPolicy.new(users(role), users(:agent_b)).index?
      refute UserPolicy.new(users(role), users(:agent_b)).update?
      refute UserPolicy.new(users(role), users(:agent_b)).create?
    end
  end

  test "users can view their own profile" do
    assert UserPolicy.new(users(:agent_a), users(:agent_a)).show?
    refute UserPolicy.new(users(:agent_a), users(:agent_b)).show?
  end

  test "admins cannot delete themselves" do
    refute UserPolicy.new(users(:admin), users(:admin)).destroy?
    assert UserPolicy.new(users(:admin), users(:agent_a)).destroy?
  end

  test "scope is admin-only" do
    assert_equal User.count, UserPolicy::Scope.new(users(:admin), User).resolve.count
    assert_empty UserPolicy::Scope.new(users(:agent_a), User).resolve
  end
end
