require "test_helper"

# C2 (forward pass) — the role-grant authority boundary across the real
# request paths: a per-tenant client_admin must not be able to mint a
# cross-tenant super_admin via the admin UI or the API.
class RoleAssignmentGuardTest < ActionDispatch::IntegrationTest
  test "the admin UI rejects a client_admin granting super_admin" do
    sign_in_as users(:client_admin)
    assert_no_difference "User.count" do
      post admin_users_path, params: { user: {
        name: "Escalate", email_address: "esc@t.test", password: "password1234", role: "super_admin"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "the admin UI allows a client_admin to create a peer client_admin" do
    sign_in_as users(:client_admin)
    assert_difference "User.count", 1 do
      post admin_users_path, params: { user: {
        name: "Peer", email_address: "peer@t.test", password: "password1234", role: "client_admin"
      } }
    end
  end

  test "a super_admin can create a super_admin via the admin UI" do
    sign_in_as users(:super_admin)
    assert_difference "User.count", 1 do
      post admin_users_path, params: { user: {
        name: "Platform2", email_address: "plat2@t.test", password: "password1234", role: "super_admin"
      } }
    end
  end

  test "the API rejects a client_admin token granting super_admin" do
    token = api_token_for(users(:client_admin))
    assert_no_difference "User.count" do
      post "/api/v1/users", params: { user: {
        name: "ApiEsc", email_address: "apiesc@t.test", password: "password1234", role: "super_admin"
      } }, headers: auth_header(token)
    end
    assert_response :unprocessable_entity
  end
end
