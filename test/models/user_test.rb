require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "deactivate! disables login and clears sessions" do
    user = users(:agent_a)
    user.sessions.create!
    user.deactivate!
    refute user.active?
    assert_empty user.sessions.reload
  end

  test "role enum stores the functional roles" do
    assert_equal %w[super_admin client_admin finance sales customer_service technical readonly],
                 User.roles.keys
  end

  test "default role is the least-privilege customer_service" do
    assert_equal "customer_service", User.new.role
  end

  test "sla target priorities mirror case priorities" do
    assert_equal Case.priorities, SlaTarget.priorities
  end

  test "email format validated" do
    user = User.new(name: "Bad", email_address: "not-an-email", password: "password1234")
    refute user.valid?
    assert user.errors[:email_address].any?
  end

  # C2 — a user can only be granted a role at or below the assigner's rank.
  def new_user(role)
    User.new(name: "N", email_address: "n#{role}@t.test", password: "password1234", role: role)
  end

  test "a client_admin assigner cannot grant a role above its own rank" do
    Current.actor = users(:client_admin)
    refute new_user(:super_admin).valid?, "client_admin must not mint a super_admin"
    assert new_user(:client_admin).valid?, "a peer-rank role is allowed"
    assert new_user(:customer_service).valid?
  ensure
    Current.actor = nil
  end

  test "a super_admin assigner may grant super_admin" do
    Current.actor = users(:super_admin)
    assert new_user(:super_admin).valid?
  ensure
    Current.actor = nil
  end

  test "system/seed context (no acting user) is unconstrained" do
    Current.actor = nil
    assert new_user(:super_admin).valid?
  end

  test "changing an existing user's role above the assigner's rank is rejected" do
    Current.actor = users(:client_admin)
    target = users(:customer_service)
    target.role = :super_admin
    refute target.valid?
    assert target.errors[:role].any?
  ensure
    Current.actor = nil
  end
end
