require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "the sign-in page loads without a session" do
    get new_session_path
    assert_response :success
  end

  test "valid credentials sign in and land on home" do
    log_in_through_form(agent)
    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
    assert_select "#role-badge", "Agent"
  end

  test "wrong password is refused" do
    log_in_through_form(agent, password: "nope")
    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "a deactivated person cannot sign in" do
    log_in_through_form(users(:inactive_agent))
    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "deactivating someone cuts off a session that is already open" do
    log_in_through_form(agent)
    get root_path
    assert_response :success
    agent.update!(active: false)
    get root_path
    assert_redirected_to new_session_path
  end

  test "signing out ends the session" do
    log_in_through_form(agent)
    delete session_path
    assert_redirected_to new_session_path
    get root_path
    assert_redirected_to new_session_path
  end

  test "visiting a page signed-out sends you to sign in, then back" do
    get root_path
    assert_redirected_to new_session_path
  end
end
