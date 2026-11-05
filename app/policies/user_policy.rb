# Agents (users). Admins manage agents and managers; only a Super User manages admins.
class UserPolicy < ApplicationPolicy
  def index? = user.at_least?(:manager)

  def show?
    record.id == user.id || (same_organization? && scope_includes_record?)
  end

  def create? = user.admin_or_above?

  # Edit an agent. Admins can edit agents and managers; admins and super users need a Super User.
  def update?
    user.admin_or_above? && same_organization? && manages_role?(record.role)
  end

  # Deactivate. Never yourself.
  def destroy? = update? && record.id != user.id

  # Move an agent between teams.
  def move_team? = update?

  # May this person give the user this role? (Stops an admin creating admins by editing the form.)
  def assign_role? = assignable_roles.include?(record.role)

  # Which roles this person may hand out when creating or editing a user.
  def assignable_roles
    return User::ROLES if user.super_user?
    return %w[agent manager] if user.admin?
    []
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.where(organization_id: user.organization_id) if user.admin_or_above?
      return scope.where(id: user.id).or(scope.where(team_id: user.accessible_teams.select(:id))) if user.manager?
      scope.where(id: user.id)
    end
  end

  private

  def same_organization? = record.organization_id == user.organization_id
  def scope_includes_record? = Scope.new(user, User).resolve.exists?(record.id)
  def manages_role?(role) = user.super_user? || %w[agent manager].include?(role.to_s)
end
