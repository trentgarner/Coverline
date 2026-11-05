class TeamsController < ApplicationController
  before_action :set_team, only: %i[show edit update destroy]
  after_action :verify_policy_scoped, only: :index

  def index
    authorize Team
    @teams = policy_scope(Team).order(:name)
    @agent_counts = User.where(team_id: @teams.select(:id), role: "agent", active: true).group(:team_id).count
    @manager_counts = TeamAccess.where(team_id: @teams.select(:id)).group(:team_id).count
  end

  def show
    authorize @team
    @agents = @team.users.where(role: "agent").order(:last_name, :first_name)
    @managers = @team.managers.order(:last_name, :first_name)
    @grantable = policy(@team).grant_access? ? User.where(organization_id: current_user.organization_id, role: "manager", active: true).where.not(id: @managers.select(:id)).order(:last_name, :first_name) : User.none
  end

  def new
    @team = Team.new(organization: current_user.organization)
    authorize @team, :create?
  end

  def create
    @team = Team.new(team_params.merge(organization: current_user.organization))
    authorize @team, :create?
    if @team.save
      AuditLog.record!(current_user, "created", @team)
      redirect_to @team, notice: "#{@team.name} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @team, :update?
  end

  def update
    authorize @team, :update?
    if @team.update(team_params)
      changes = AuditLog.diff(@team)
      AuditLog.record!(current_user, "renamed", @team, changes) if changes.any?
      Board::Broadcaster.roster_changed(current_user.organization, @team)
      redirect_to @team, notice: "Team saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @team, :destroy?
    if @team.users.exists?
      redirect_to @team, alert: "Move or deactivate this team's #{@team.users.count} people first, then delete it.", status: :see_other
    else
      @team.destroy!
      AuditLog.record!(current_user, "deleted", @team)
      redirect_to teams_path, notice: "#{@team.name} deleted.", status: :see_other
    end
  end

  private

  # Agents are turned away here; a manager asking for a team that isn't theirs gets a 404.
  def set_team
    authorize Team, :index?
    @team = policy_scope(Team).find(params[:id])
  end
  def team_params = params.require(:team).permit(:name)
end
