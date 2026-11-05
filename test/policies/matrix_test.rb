require "test_helper"

# The permission matrix from plan section 2, row for row. Columns are
# [Agent, Manager, Admin, Super User]. If the plan's table changes, change this table.
class MatrixTest < ActiveSupport::TestCase
  ROLES = { agent: :agent_a1, manager: :manager_ab, admin: :admin, super_user: :super }.freeze

  # Each row: label, expected [agent, manager, admin, super_user], check(user) -> true/false
  MATRIX = [
    [ "See own status, time in status, adherence", [ true, true, true, true ],
      ->(u) { BoardPolicy.new(u, :board).view_own? } ],
    [ "See live board", [ false, true, true, true ],
      ->(u) { BoardPolicy.new(u, :board).view? } ],
    [ "Change an agent's status manually (an agent on Team A)", [ false, true, true, true ],
      ->(u) { BoardPolicy.new(u, User.find_by!(email_address: "alex@example.com")).override_status? } ],
    [ "Add agents", [ false, false, true, true ],
      ->(u) { UserPolicy.new(u, User).create? } ],
    [ "Edit agents", [ false, false, true, true ],
      ->(u) { UserPolicy.new(u, User.find_by!(email_address: "alex@example.com")).update? } ],
    [ "Move agents between teams", [ false, false, true, true ],
      ->(u) { UserPolicy.new(u, User.find_by!(email_address: "alex@example.com")).move_team? } ],
    [ "Create teams", [ false, false, true, true ],
      ->(u) { TeamPolicy.new(u, Team).create? } ],
    [ "Edit teams", [ false, false, true, true ],
      ->(u) { TeamPolicy.new(u, Team.find_by!(name: "Sales Team A")).update? } ],
    [ "Grant managers access to teams", [ false, false, true, true ],
      ->(u) { TeamPolicy.new(u, Team.find_by!(name: "Sales Team A")).grant_access? } ],
    [ "Edit schedules", [ false, false, true, true ],
      ->(u) { SchedulePolicy.new(u, :schedule).update? } ],
    [ "Add statuses", [ false, false, true, true ],
      ->(u) { StatusPolicy.new(u, :status).create? } ],
    [ "Edit statuses, colors, phone codes", [ false, false, true, true ],
      ->(u) { StatusPolicy.new(u, :status).update? } ],
    [ "Manage admins", [ false, false, false, true ],
      ->(u) { OrganizationPolicy.new(u, :organization).manage_admins? } ],
    [ "Manage phone integration", [ false, false, false, true ],
      ->(u) { OrganizationPolicy.new(u, :organization).manage_integration? } ],
    [ "Manage org settings", [ false, false, false, true ],
      ->(u) { OrganizationPolicy.new(u, :organization).manage_settings? } ],
    [ "See audit log", [ false, false, true, true ],
      ->(u) { AuditLogPolicy.new(u, :audit_log).index? } ],
    # Section 7 puts Targets under Admin and Super User (see the note on section 2 vs 7 in the Phase 1 summary)
    [ "Change TST/CFT targets and grace periods", [ false, false, true, true ],
      ->(u) { OrganizationPolicy.new(u, :organization).update_targets? } ]
  ].freeze

  MATRIX.each do |label, expected, check|
    ROLES.each_with_index do |(role, fixture), i|
      test "#{label}: #{role} #{expected[i] ? 'can' : 'cannot'}" do
        assert_equal expected[i], check.call(users(fixture)), "#{label} for #{role}"
      end
    end
  end

  test "everyone signed in can see the status list" do
    ROLES.each_value { |f| assert StatusPolicy.new(users(f), :status).index?, f }
  end

  test "policies refuse to work without a signed-in user" do
    assert_raises(Pundit::NotAuthorizedError) { BoardPolicy.new(nil, :board) }
    assert_raises(Pundit::NotAuthorizedError) { UserPolicy::Scope.new(nil, User) }
  end
end
