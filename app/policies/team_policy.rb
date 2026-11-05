class TeamPolicy < ApplicationPolicy
  def index? = user.at_least?(:manager)
  def show? = user.at_least?(:manager) && same_organization? && Scope.new(user, Team).resolve.exists?(record.id)
  def create? = user.admin_or_above?
  def update? = user.admin_or_above? && same_organization?
  def destroy? = update?

  # Grant a manager access to a team.
  def grant_access? = update?

  class Scope < ApplicationPolicy::Scope
    # Admins and up see every team; managers only the teams they were granted.
    def resolve = scope.all.merge(user.visible_teams)
  end

  private

  def same_organization? = !record.is_a?(Team) || record.organization_id == user.organization_id
end
