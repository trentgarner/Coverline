require "test_helper"

class AgentsTest < ActionDispatch::IntegrationTest
  def new_agent_params(overrides = {})
    { user: { first_name: "Nia", last_name: "Newhire", email_address: "nia@example.com", phone_agent_id: "A2001",
              team_id: teams(:team_a).id, role: "agent", password: "temp-pass-123" }.merge(overrides) }
  end

  test "an admin adds an agent with a temporary password, who can then sign in" do
    sign_in_as admin
    assert_difference "User.count", 1 do
      post agents_path, params: new_agent_params
    end
    nia = User.find_by!(email_address: "nia@example.com")
    assert_equal [ "agent", teams(:team_a), "A2001", organizations(:summit) ], [ nia.role, nia.team, nia.phone_agent_id, nia.organization ]
    assert_redirected_to agents_path(role: "agent")
    delete session_path
    log_in_through_form(nia, password: "temp-pass-123")
    assert_redirected_to root_url
  end

  test "creating an agent is audited, without the password" do
    sign_in_as admin
    post agents_path, params: new_agent_params
    log = AuditLog.where(action: "created", target_type: "User").last
    assert_equal admin, log.user
    assert_equal "Nia Newhire", log.target_label
    assert_no_match(/temp-pass/, log.details.to_json)
  end

  test "required fields and short passwords are rejected with messages" do
    sign_in_as admin
    assert_no_difference "User.count" do
      post agents_path, params: new_agent_params(first_name: "", password: "short")
    end
    assert_response :unprocessable_entity
    assert_select ".alert-danger", /First name/
    assert_select ".alert-danger", /Password/
  end

  test "an admin can add a manager but cannot create an admin or super user, even by editing the form" do
    sign_in_as admin
    assert_difference "User.count", 1 do
      post agents_path, params: new_agent_params(role: "manager", email_address: "mgr@example.com")
    end
    assert_nil User.find_by!(email_address: "mgr@example.com").team_id, "managers don't belong to a team"
    %w[admin super_user].each do |role|
      assert_no_difference "User.count" do
        post agents_path, params: new_agent_params(role: role, email_address: "#{role}@example.com")
      end
      assert_redirected_to root_path
    end
  end

  test "an unknown role value is refused" do
    sign_in_as admin
    assert_no_difference "User.count" do
      post agents_path, params: new_agent_params(role: "owner")
    end
    assert_redirected_to root_path
    patch agent_path(agent), params: { user: { role: "root" } }
    assert agent.reload.agent?
  end

  test "a super user can create an admin" do
    sign_in_as super_user
    assert_difference "User.count", 1 do
      post agents_path, params: new_agent_params(role: "admin", email_address: "newadmin@example.com")
    end
    assert User.find_by!(email_address: "newadmin@example.com").admin?
  end

  test "an admin cannot promote an agent to admin, nor edit an admin" do
    sign_in_as admin
    patch agent_path(agent), params: { user: { role: "admin" } }
    assert_redirected_to root_path
    assert agent.reload.agent?
    get edit_agent_path(users(:second_admin))
    assert_redirected_to root_path
  end

  test "editing changes details, keeps the password unless a new one is given, and logs the changes" do
    sign_in_as admin
    patch agent_path(agent), params: { user: { first_name: "Alexa", phone_agent_id: "A9999", password: "" } }
    assert_redirected_to agents_path(role: "agent")
    agent.reload
    assert_equal [ "Alexa", "A9999" ], [ agent.first_name, agent.phone_agent_id ]
    assert User.authenticate_by(email_address: agent.email_address, password: "password"), "blank password keeps the old one"
    log = AuditLog.where(action: "updated", target_type: "User", target_id: agent.id).last
    assert_equal({ "first_name" => %w[Alex Alexa], "phone_agent_id" => %w[A1001 A9999] }, log.changes_hash)

    patch agent_path(agent), params: { user: { password: "brand-new-pass" } }
    assert User.authenticate_by(email_address: agent.email_address, password: "brand-new-pass")
    assert AuditLog.exists?(action: "password_reset", target_id: agent.id)
  end

  test "moving an agent to another team via edit is logged as a team move" do
    sign_in_as admin
    patch agent_path(agent), params: { user: { team_id: teams(:team_c).id } }
    assert_equal teams(:team_c), agent.reload.team
    log = AuditLog.where(action: "moved_team", target_id: agent.id).last
    assert_equal({ "team" => [ "Sales Team A", "Sales Team C" ] }, log.changes_hash)
  end

  test "an agent can't be put on a team in another organization" do
    sign_in_as admin
    patch agent_path(agent), params: { user: { team_id: teams(:other_team).id } }
    assert_response :unprocessable_entity
    assert_equal teams(:team_a), agent.reload.team
  end

  test "deactivating blocks sign-in and reactivating restores it" do
    sign_in_as admin
    patch deactivate_agent_path(agent)
    assert_not agent.reload.active?
    assert AuditLog.exists?(action: "deactivated", target_id: agent.id)
    delete session_path
    log_in_through_form(agent)
    assert_redirected_to new_session_path
    sign_in_as admin
    patch reactivate_agent_path(agent)
    assert agent.reload.active?
  end

  test "you cannot deactivate yourself" do
    sign_in_as admin
    patch deactivate_agent_path(admin)
    assert_redirected_to root_path
    assert admin.reload.active?
  end

  test "bulk move sends the ticked agents to another team and logs each move" do
    sign_in_as admin
    post bulk_move_agents_path, params: { ids: [ users(:agent_a1).id, users(:agent_a2).id ], team_id: teams(:team_c).id }
    assert_equal [ teams(:team_c), teams(:team_c) ], [ users(:agent_a1).reload.team, users(:agent_a2).reload.team ]
    assert_equal 2, AuditLog.where(action: "moved_team").count
  end

  test "bulk move ignores managers and people in other organizations" do
    sign_in_as admin
    post bulk_move_agents_path, params: { ids: [ users(:manager_ab).id, users(:other_agent).id ], team_id: teams(:team_c).id }
    assert_redirected_to agents_path
    assert_nil users(:manager_ab).reload.team_id
    assert_equal teams(:other_team), users(:other_agent).reload.team
  end

  test "the list filters by role, team, active and search" do
    sign_in_as admin
    get agents_path, params: { role: "agent", team_id: teams(:team_a).id }
    assert_select "#agents tbody tr[data-user]", 3 # Alex, Avery, Idle (inactive)
    get agents_path, params: { role: "agent", team_id: teams(:team_a).id, active: "1" }
    assert_select "#agents tbody tr[data-user]", 2
    get agents_path, params: { q: "blake" }
    assert_select "#agents tbody tr[data-user]", 1
    get agents_path, params: { q: "A1002" }
    assert_select "tr[data-user='avery@example.com']"
  end

  test "an admin never sees people from another organization, and can't open them" do
    sign_in_as admin
    get agents_path
    assert_select "tr[data-user='otto@other.example.com']", false
    get edit_agent_path(users(:other_agent))
    assert_response :not_found
    patch agent_path(users(:other_agent)), params: { user: { first_name: "Hacked" } }
    assert_response :not_found
  end

  test "managers see only their teams' people, read-only" do
    sign_in_as manager
    get agents_path
    assert_response :success
    assert_select "tr[data-user='blake@example.com']"
    assert_select "tr[data-user='casey@example.com']", false
    assert_select "a", text: "Add person", count: 0
    assert_select "a", text: "Edit", count: 0
    get new_agent_path
    assert_redirected_to root_path
    patch agent_path(users(:agent_a1)), params: { user: { first_name: "Nope" } }
    assert_redirected_to root_path
    assert_equal "Alex", users(:agent_a1).reload.first_name
  end

  test "agents can't open any of the admin screens" do
    sign_in_as agent
    [ agents_path, new_agent_path, bulk_new_agents_path, edit_agent_path(users(:agent_a2)) ].each do |path|
      get path
      assert_redirected_to root_path, path
    end
  end

  test "signed-out visitors are sent to sign in" do
    get agents_path
    assert_redirected_to new_session_path
  end

  test "bulk add: paste a list, everyone lands on the team with a one-time password" do
    sign_in_as admin
    list = "Ivy, Archer, ivy.archer@example.com, A3001\nJude\tBellamy\tjude.bellamy@example.com\tA3002\nKai, Calder, kai.calder@example.com\n"
    assert_difference "User.count", 3 do
      post bulk_create_agents_path, params: { team_id: teams(:team_b).id, list: list }
    end
    assert_response :success
    assert_select "#new-credentials tbody tr", 3
    ivy = User.find_by!(email_address: "ivy.archer@example.com")
    assert_equal [ teams(:team_b), "agent", "A3001" ], [ ivy.team, ivy.role, ivy.phone_agent_id ]
    password = css_select("#new-credentials tbody tr:first-child td.font-monospace").first.text
    assert_equal 10, password.size
    assert User.authenticate_by(email_address: "ivy.archer@example.com", password: password)
    assert_equal "bulk_created", AuditLog.last.action
    assert_nil User.find_by!(email_address: "kai.calder@example.com").phone_agent_id
  end

  test "bulk add is all or nothing and explains each problem" do
    sign_in_as admin
    list = "Ivy, Archer, ivy.archer@example.com\nOops, NoEmail\nAlex, Dup, alex@example.com\n"
    assert_no_difference "User.count" do
      post bulk_create_agents_path, params: { team_id: teams(:team_b).id, list: list }
    end
    assert_response :unprocessable_entity
    assert_select ".alert-danger", /Line 2/
    assert_select "textarea", /Ivy, Archer/, "keeps what you pasted"

    assert_no_difference "User.count" do
      post bulk_create_agents_path, params: { team_id: teams(:team_b).id, list: "Ivy, Archer, ivy.archer@example.com\nAlex, Dup, alex@example.com" }
    end
    assert_select ".alert-danger", /Email/
    assert_not User.exists?(email_address: "ivy.archer@example.com"), "the good line is rolled back too"
  end

  test "bulk add needs a team from your own organization and some lines" do
    sign_in_as admin
    post bulk_create_agents_path, params: { team_id: "", list: "Ivy, Archer, ivy.archer@example.com" }
    assert_select ".alert-danger", /Choose a team/
    post bulk_create_agents_path, params: { team_id: teams(:other_team).id, list: "Ivy, Archer, ivy.archer@example.com" }
    assert_select ".alert-danger", /Choose a team/
    post bulk_create_agents_path, params: { team_id: teams(:team_a).id, list: "  \n " }
    assert_select ".alert-danger", /Nothing to add/
  end

  test "only admins and up can bulk add" do
    sign_in_as manager
    assert_no_difference "User.count" do
      post bulk_create_agents_path, params: { team_id: teams(:team_a).id, list: "Ivy, Archer, ivy.archer@example.com" }
    end
    assert_redirected_to root_path
  end
end
