require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "records who did what to whom, keeping the name at the time" do
    log = AuditLog.record!(admin, "updated", agent, "last_name" => %w[Agent Renamed])
    assert_equal [ admin.id, "updated", "User", agent.id, "Alex Agent" ], [ log.user_id, log.action, log.target_type, log.target_id, log.target_label ]
    assert_equal({ "last_name" => %w[Agent Renamed] }, log.changes_hash)
  end

  test "diff leaves out passwords and timestamps" do
    u = agent
    u.update!(first_name: "Alexa", password: "a-new-password")
    diff = AuditLog.diff(u)
    assert_equal %w[first_name], diff.keys
  end

  test "scoped to the organization of the person who made the change" do
    mine = AuditLog.record!(admin, "created", teams(:team_a))
    theirs = AuditLog.record!(users(:other_admin), "created", teams(:other_team))
    scoped = AuditLog.for_organization(organizations(:summit))
    assert_includes scoped, mine
    assert_not_includes scoped, theirs
  end

  test "a deleted target still reads correctly" do
    log = AuditLog.record!(admin, "deleted", teams(:team_c))
    teams(:team_c).destroy
    assert_equal "Sales Team C", log.reload.target_label
  end
end
