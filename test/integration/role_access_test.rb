require "test_helper"

# Phase 1 "done when": each of the 4 roles logs in and sees only what the matrix allows.
class RoleAccessTest < ActionDispatch::IntegrationTest
  ALL_CAPABILITIES = %w[view_own view_board override_status add_agents move_agents manage_teams grant_access
                        edit_schedules edit_statuses edit_targets manage_org audit_log].freeze

  EXPECTED = {
    agent: %w[view_own],
    manager: %w[view_own view_board override_status],
    admin: %w[view_own view_board override_status add_agents move_agents manage_teams grant_access edit_schedules edit_statuses edit_targets audit_log],
    super_user: ALL_CAPABILITIES
  }.freeze

  def allowed_on_page
    css_select("#capabilities li[data-allowed=true]").map { |li| li["data-capability"] }
  end

  def denied_on_page
    css_select("#capabilities li[data-allowed=false]").map { |li| li["data-capability"] }
  end

  { agent: :agent_a1, manager: :manager_ab, admin: :admin, super_user: :super }.each do |role, fixture|
    test "#{role} signs in and the home page shows exactly the matrix" do
      log_in_through_form(users(fixture))
      follow_redirect!
      assert_response :success
      assert_select "#role-badge", role == :super_user ? "Super User" : role.to_s.capitalize
      assert_equal EXPECTED[role].sort, allowed_on_page.sort
      assert_equal (ALL_CAPABILITIES - EXPECTED[role]).sort, denied_on_page.sort
    end
  end

  test "an agent sees only themselves and no teams" do
    log_in_through_form(agent)
    follow_redirect!
    assert_select "#teams", false
    assert_select "#people [data-person]", 1
    assert_select "#people [data-person='alex@example.com']"
  end

  test "a manager sees only their teams and those teams' people" do
    log_in_through_form(manager)
    follow_redirect!
    assert_select "#teams [data-team]", 2
    assert_select "#teams [data-team='Sales Team A']"
    assert_select "#teams [data-team='Sales Team B']"
    assert_select "#teams [data-team='Sales Team C']", false
    assert_select "#people [data-person='blake@example.com']"
    assert_select "#people [data-person='casey@example.com']", false
  end

  test "an admin sees every team and person in the organization, and nobody from another" do
    log_in_through_form(admin)
    follow_redirect!
    assert_select "#teams [data-team]", 3
    assert_select "#people [data-person]", 10
    assert_select "#people [data-person='casey@example.com']"
    assert_select "#people [data-person='otto@other.example.com']", false
  end

  test "another organization's admin sees only their own" do
    log_in_through_form(users(:other_admin))
    follow_redirect!
    assert_select "#teams [data-team]", 1
    assert_select "#people [data-person]", 2
    assert_select "#people [data-person='alex@example.com']", false
  end

  test "pages require signing in" do
    get root_path
    assert_redirected_to new_session_path
  end
end
