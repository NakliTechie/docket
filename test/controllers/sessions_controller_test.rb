require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "create with missing credential keys fails gracefully, not a 500 (L)" do
    post session_path, params: { email_address: @user.email_address } # no password key
    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]

    post session_path, params: {} # neither key
    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "login returns to the GET page that bounced, surviving session rotation (L)" do
    get cases_path # protected; unauthenticated → bounce + store return_to
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to cases_url # reset_session preserved the return_to
  end

  test "a POST that hits the auth wall is not stored as return_to (no 404 after login) (L)" do
    post cases_path, params: { case: { subject: "x" } } # protected POST; unauthenticated
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to root_url # not the un-GETtable POST path
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
