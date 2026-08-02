require "test_helper"

class AdminRecordScopesTest < ActionDispatch::IntegrationTest
  test "an administrator creates a team and assigns independent user scopes" do
    sign_in_as users(:admin)

    assert_difference "Team.count", 1 do
      post admin_teams_path, params: { team: {
        name: "Field response", description: "Regional specialists",
        member_ids: [ users(:agent_a).id, users(:agent_b).id ]
      } }
    end
    team = Team.find_by!(name: "Field response")
    assert_equal [ users(:agent_a).id, users(:agent_b).id ].sort, team.member_ids.sort

    patch admin_user_path(users(:agent_a)), params: { user: {
      name: users(:agent_a).name, email_address: users(:agent_a).email_address,
      role: users(:agent_a).role, record_read_scope: "team",
      record_write_scope: "assigned", team_ids: [ team.id ],
      scoped_account_ids: [ organisations(:dpg).id ]
    } }
    assert_redirected_to admin_users_path

    user = users(:agent_a).reload
    assert_equal "team", user.record_read_scope
    assert_equal "assigned", user.record_write_scope
    assert_equal [ team.id ], user.team_ids
    assert_equal [ organisations(:dpg).id ], user.scoped_account_ids
  end

  test "an administrator cannot change their own scope assignment" do
    user = users(:client_admin)
    sign_in_as user

    patch admin_user_path(user), params: { user: {
      name: user.name, email_address: user.email_address, role: user.role,
      record_read_scope: "owned", record_write_scope: "owned"
    } }

    assert_response :unprocessable_entity
    assert_equal "global", user.reload.record_read_scope
    assert_equal "global", user.record_write_scope
  end

  test "a team member cannot edit that team's membership or delete it" do
    team = Team.create!(name: "Managed elsewhere", member_ids: [ users(:client_admin).id, users(:agent_a).id ])
    sign_in_as users(:client_admin)

    patch admin_team_path(team), params: { team: {
      name: team.name, member_ids: [ users(:client_admin).id, users(:agent_b).id ]
    } }
    assert_response :unprocessable_entity
    assert_equal [ users(:client_admin).id, users(:agent_a).id ].sort, team.reload.member_ids.sort

    assert_no_difference "Team.count" do
      delete admin_team_path(team)
    end
    assert_response :unprocessable_entity
  end

  test "the user API validates and serializes record scopes" do
    token = api_token_for(users(:admin))

    patch "/api/v1/users/#{users(:agent_b).id}", params: { user: {
      record_read_scope: "queue", record_write_scope: "assigned",
      scoped_account_ids: [ organisations(:branch).id ]
    } }, headers: auth_header(token), as: :json
    assert_response :success
    payload = response.parsed_body.fetch("data")
    assert_equal "queue", payload.fetch("record_read_scope")
    assert_equal "assigned", payload.fetch("record_write_scope")
    assert_equal [ organisations(:branch).id ], payload.fetch("scoped_account_ids")

    patch "/api/v1/users/#{users(:agent_b).id}", params: {
      user: { record_read_scope: "planet" }
    }, headers: auth_header(token), as: :json
    assert_response :unprocessable_entity
  end

  test "a non-manager cannot open team administration" do
    sign_in_as users(:agent_a)
    get admin_teams_path
    assert_response :forbidden
  end
end
