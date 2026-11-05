# Statuses (name, color, category, phone codes). Everyone signed in can see them
# (the board and your own status need the colors); only admins and up change them.
class StatusPolicy < ApplicationPolicy
  def index? = true # everyone signed in can read the list (the board needs the colors)
  def manage? = user.admin_or_above? # the Statuses admin screen
  def show? = true
  def create? = user.admin_or_above?
  def update? = user.admin_or_above?
  def destroy? = user.admin_or_above?
  def reorder? = update?

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.where(organization_id: user.organization_id)
  end
end
