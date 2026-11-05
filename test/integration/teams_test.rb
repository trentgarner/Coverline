require "test_helper"

class TeamsTest < ActionDispatch::IntegrationTest
  test "an admin creates, renames and deletes an empty team, with an audit trail" do
    sign_in_as admin
    assert_difference "Team.count", 1 do
      post teams_path, params: { team: { name: "Sales Team D" } }
    end
    team = Team.find_by!(name: "Sales Team D")
    assert_redirected_to team_path(team)
    patch team_path(team), params: { team: { name: "Sales Team Delta" } }
    assert_equal "Sales Team Delta", team.reload.name
    assert_equal({ "name" => [ "Sales Team D", "Sales Team Delta" ] }, AuditLog.where(action: "renamed").last.changes_hash)
    assert_difference "Team.count", -1 do
      delete team_path(team)
    end
    assert_equal %w[created renamed deleted], AuditLog.where(target_type: "Team").order(:id).last(3).map(&:action)
  end

  test "names are required and unique in the organization" do
    sign_in_as admin
    assert_no_difference "Team.count" do
      post teams_path, params: { team: { name: "" } }
      post teams_path, params: { team: { name: "Sales Team A" } }
    end
    assert_response :unprocessable_entity
  end

  test "a team with people on it can't be deleted" do
    sign_in_as admin
    assert_no_difference "Team.count" do
      delete team_path(teams(:team_a))
    end
    assert_redirected_to team_path(teams(:team_a))
    follow_redirect!
    assert_select ".alert-danger", /Move or deactivate/
  end

  test "the team page lists members and the managers who can see it" do
    sign_in_as admin
    get team_path(teams(:team_a))
    assert_select "#members [data-member]", 3
    assert_select "#managers [data-manager='maya@example.com']"
    assert_select "#managers [data-manager='marco@example.com']", false
  end

  test "an admin grants a manager access, and the manager then sees the team" do
    sign_in_as admin
    assert_difference "TeamAccess.count", 1 do
      post team_team_accesses_path(teams(:team_a)), params: { user_id: users(:manager_c).id }
    end
    assert AuditLog.exists?(action: "granted_access", target_id: teams(:team_a).id)
    delete session_path
    sign_in_as users(:manager_c)
    get teams_path
    assert_select "tr[data-team='Sales Team A']"
    assert_select "tr[data-team='Sales Team C']"
    assert_select "tr[data-team='Sales Team B']", false
  end

  test "revoking access removes the team from the manager's view" do
    sign_in_as admin
    access = team_access(:maya_team_b)
    assert_difference "TeamAccess.count", -1 do
      delete team_team_access_path(teams(:team_b), access)
    end
    assert AuditLog.exists?(action: "revoked_access")
    delete session_path
    sign_in_as manager
    get teams_path
    assert_select "tr[data-team='Sales Team B']", false
  end

  test "only managers can be granted access, and only ones in this organization" do
    sign_in_as admin
    assert_no_difference "TeamAccess.count" do
      post team_team_accesses_path(teams(:team_a)), params: { user_id: users(:agent_a1).id }
      assert_response :not_found
    end
    post team_team_accesses_path(teams(:team_a)), params: { user_id: users(:manager_ab).id } # duplicate
    follow_redirect!
    assert_select ".alert-danger", /already been taken/
  end

  test "an admin can't reach another organization's team" do
    sign_in_as admin
    get team_path(teams(:other_team))
    assert_response :not_found
    patch team_path(teams(:other_team)), params: { team: { name: "Hacked" } }
    assert_response :not_found
    post team_team_accesses_path(teams(:other_team)), params: { user_id: users(:manager_ab).id }
    assert_response :not_found
  end

  test "managers see their teams read-only and cannot change anything" do
    sign_in_as manager
    get teams_path
    assert_select "tr[data-team]", 2
    assert_select "a", text: "New team", count: 0
    get team_path(teams(:team_a))
    assert_response :success
    assert_select "a", text: "Rename", count: 0
    assert_select "button", text: "Delete", count: 0
    assert_select "button", text: "Grant access", count: 0

    get team_path(teams(:team_c))
    assert_response :not_found # not one of theirs
    assert_no_difference [ "Team.count", "TeamAccess.count" ] do
      post teams_path, params: { team: { name: "Sneaky" } }
      post team_team_accesses_path(teams(:team_a)), params: { user_id: users(:manager_c).id }
      delete team_path(teams(:team_a))
    end
  end

  test "agents can't see the teams screens" do
    sign_in_as agent
    get teams_path
    assert_redirected_to root_path
    get team_path(teams(:team_a))
    assert_redirected_to root_path
  end
end
