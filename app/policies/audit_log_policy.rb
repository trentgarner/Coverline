class AuditLogPolicy < ApplicationPolicy
  def index? = user.admin_or_above?
  def show? = index?

  class Scope < ApplicationPolicy::Scope
    def resolve = user.admin_or_above? ? scope.for_organization(user.organization) : scope.none
  end
end
