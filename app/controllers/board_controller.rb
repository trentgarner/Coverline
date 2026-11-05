# The live board: every agent you may see, grouped by team, updating as statuses change.
class BoardController < ApplicationController
  after_action :verify_policy_scoped

  def show
    authorize :board, :view?
    @teams = policy_scope(Team).order(:name)
    agents = policy_scope(User).where(role: "agent", active: true).includes(:team, :organization).order(:last_name, :first_name)
    @rows = Board::Snapshot.rows_for(agents)
    @groups = @rows.group_by { |row| row.user.team }.sort_by { |team, _| team&.name.to_s.downcase }
    @statuses = policy_scope(Status).active.ordered
    @organization = current_user.organization
    # Admins and up watch the whole organization; managers watch the teams they were granted.
    @stream_sources = current_user.admin_or_above? ? [ [ @organization, :board ] ] : @teams.map { |team| [ team, :board ] }
    @day_start = Time.zone.now.beginning_of_day
  end
end
