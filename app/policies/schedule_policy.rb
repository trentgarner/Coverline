# Daily schedules. Viewing follows team visibility; editing is admin and up.
# record may be a User (whose schedule) or :schedule.
class SchedulePolicy < ApplicationPolicy
  def show?
    return true unless record.is_a?(User)
    UserPolicy.new(user, record).show?
  end

  def index? = user.at_least?(:manager)
  def create? = user.admin_or_above?
  def update? = user.admin_or_above?
  def destroy? = user.admin_or_above?
end
