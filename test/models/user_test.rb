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
end
