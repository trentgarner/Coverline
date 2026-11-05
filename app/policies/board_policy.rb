# The live board. Headless (authorize :board, :view?) except override_status?,
# which takes the agent whose status would be changed.
class BoardPolicy < ApplicationPolicy
  # Every role can see their own status, time in status and adherence.
  def view_own? = true

  # Managers and above can see the live board (managers: assigned teams only,
  # enforced by TeamPolicy::Scope / UserPolicy::Scope).
  def view? = user.at_least?(:manager)

  # Change an agent's status by hand: managers on their own teams, admins and up on anyone in the org.
  def override_status?
    return false unless record.is_a?(User) && record.organization_id == user.organization_id
    return true if user.admin_or_above?
    user.manager? && record.team_id.present? && user.accessible_teams.exists?(record.team_id)
  end
end
