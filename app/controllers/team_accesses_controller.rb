# Grant or revoke a manager's access to a team.
class TeamAccessesController < ApplicationController
  before_action :set_team

  def create
    authorize @team, :grant_access?
    manager = User.where(organization_id: current_user.organization_id, role: "manager").find(params[:user_id])
    access = TeamAccess.new(user: manager, team: @team)
    if access.save
      AuditLog.record!(current_user, "granted_access", @team, "manager" => manager.full_name)
      redirect_to @team, notice: "#{manager.full_name} can now see #{@team.name}."
    else
      redirect_to @team, alert: access.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @team, :grant_access?
    access = @team.team_accesses.find(params[:id])
    name = access.user.full_name
    access.destroy!
    AuditLog.record!(current_user, "revoked_access", @team, "manager" => name)
    redirect_to @team, notice: "#{name} no longer sees #{@team.name}.", status: :see_other
  end

  private

  def set_team
    authorize Team, :index?
    @team = policy_scope(Team).find(params[:team_id])
  end
end
