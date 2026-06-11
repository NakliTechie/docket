require "test_helper"

class SecurityEventsTest < ActionDispatch::IntegrationTest
  test "a failed login records a security event with the attempted email + ip (L)" do
    assert_difference "SecurityEvent.where(kind: 'login_failed').count", 1 do
      post session_path, params: { email_address: users(:admin).email_address, password: "wrong" }
    end
    event = SecurityEvent.order(:id).last
    assert_equal users(:admin).email_address, event.email
    assert event.ip_address.present?
  end

  test "missing credentials also record a failed login, not a 500 (L)" do
    assert_difference "SecurityEvent.where(kind: 'login_failed').count", 1 do
      post session_path, params: { email_address: "ghost@example.com" } # no password key
    end
    assert_redirected_to new_session_path
  end

  test "a successful login records no security event" do
    assert_no_difference "SecurityEvent.count" do
      post session_path, params: { email_address: users(:admin).email_address, password: "password" }
    end
  end

  test "admin can view the security log" do
    SecurityEvent.record("login_failed", email: "attacker@example.com", ip_address: "10.0.0.9")
    sign_in_as users(:admin)
    get admin_security_events_path
    assert_response :success
    assert_match "attacker@example.com", response.body
  end

  test "non-admins cannot view the security log" do
    sign_in_as users(:supervisor)
    get admin_security_events_path
    assert_response :forbidden
  end

  test "recording never raises from the auth path" do
    assert_nothing_raised do
      assert_nil SecurityEvent.record("not_a_known_kind", email: "x@example.com")
    end
  end
end
