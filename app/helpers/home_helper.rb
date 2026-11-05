module HomeHelper
  Capability = Struct.new(:key, :label, :allowed, keyword_init: true)

  # The permission matrix (plan section 2) as the signed-in person sees it.
  def capabilities_for(user)
    can = ->(record, query, policy_class = nil) { (policy_class ? policy_class.new(user, record) : Pundit.policy!(user, record)).public_send(query) }
    some_agent = User.new(role: "agent", organization_id: user.organization_id, team_id: user.team_id)
    [
      [ "view_own", "See own status, time in status, adherence", can.(:board, :view_own?, BoardPolicy) ],
      [ "view_board", "See the live board for your teams", can.(:board, :view?, BoardPolicy) ],
      [ "override_status", "Change an agent's status manually", user.at_least?(:manager) && (user.admin_or_above? || user.visible_teams.any?) ],
      [ "add_agents", "Add and edit agents", UserPolicy.new(user, User).create? ],
      [ "move_agents", "Move agents between teams", UserPolicy.new(user, some_agent).move_team? ],
      [ "manage_teams", "Create and edit teams", TeamPolicy.new(user, Team).create? ],
      [ "grant_access", "Grant managers access to teams", TeamPolicy.new(user, Team.new(organization_id: user.organization_id)).grant_access? ],
      [ "edit_schedules", "Edit schedules", can.(:schedule, :update?, SchedulePolicy) ],
      [ "edit_statuses", "Add and edit statuses, colors and phone codes", can.(:status, :update?, StatusPolicy) ],
      [ "edit_targets", "Change TST/CFT targets and grace periods", can.(:organization, :update_targets?, OrganizationPolicy) ],
      [ "manage_org", "Manage admins, phone integration and org settings", can.(:organization, :manage_settings?, OrganizationPolicy) ],
      [ "audit_log", "See the audit log", can.(:audit_log, :index?, AuditLogPolicy) ]
    ].map { |key, label, allowed| Capability.new(key: key, label: label, allowed: !!allowed) }
  end

  ROLE_LABELS = { "agent" => "Agent", "manager" => "Manager", "admin" => "Admin", "super_user" => "Super User" }.freeze
  def role_label(role) = ROLE_LABELS.fetch(role.to_s, role.to_s.humanize)
end
