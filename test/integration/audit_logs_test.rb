require "test_helper"

class AuditLogsTest < ActionDispatch::IntegrationTest
  setup do
    AuditLog.record!(admin, "moved_team", agent, "team" => [ "Sales Team A", "Sales Team C" ])
    AuditLog.record!(super_user, "created", teams(:team_a))
    AuditLog.record!(users(:other_admin), "created", teams(:other_team))
  end

  test "admins and super users see their organization's log, newest first, with details" do
    [ admin, super_user ].each do |u|
      sign_in_as u
      get audit_logs_path
      assert_response :success
      assert_select "#audit-log tbody tr", 2
      assert_select "#audit-log", /Alex Agent/
      assert_select "#audit-log", /Sales Team A → Sales Team C/
      assert_select "#audit-log", { text: /Other Team/, count: 0 }
      delete session_path
    end
  end

  test "filter by who and by action" do
    sign_in_as admin
    get audit_logs_path, params: { user_id: admin.id }
    assert_select "#audit-log tbody tr", 1
    get audit_logs_path, params: { action_name: "created" }
    assert_select "#audit-log tbody tr", 1
  end

  test "managers and agents can't open it" do
    [ manager, agent ].each do |u|
      sign_in_as u
      get audit_logs_path
      assert_redirected_to root_path
      delete session_path
    end
  end

  test "pages through long logs" do
    55.times { |i| AuditLog.record!(admin, "updated", agent, "n" => i) }
    sign_in_as admin
    get audit_logs_path
    assert_select "#audit-log tbody tr", 50
    assert_select "a", "Older →"
    get audit_logs_path, params: { page: 2 }
    assert_select "#audit-log tbody tr", 7
    assert_select "a", { text: "Older →", count: 0 }
  end
end
