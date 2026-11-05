# "Agents" screen: everyone who can be scheduled or log in (agents, plus the managers an
# admin adds). Admins and Super Users add and edit them; managers see their own teams read-only.
class AgentsController < ApplicationController
  before_action :set_user, only: %i[show edit update deactivate reactivate override_status]
  after_action :verify_policy_scoped, only: :index

  def index
    authorize User
    @teams = policy_scope(Team).order(:name)
    users = policy_scope(User).includes(:team).order(:last_name, :first_name)
    @role = params[:role].presence_in(User::ROLES)
    users = users.where(role: @role) if @role
    users = users.where(team_id: params[:team_id]) if params[:team_id].present?
    users = users.where(active: params[:active] == "1") if params[:active].present?
    users = users.where("first_name ILIKE :q OR last_name ILIKE :q OR email_address ILIKE :q OR phone_agent_id ILIKE :q", q: "%#{params[:q].strip}%") if params[:q].present?
    @users = users
  end

  # One person: current status, today's changes, and (for managers/admins) the manual override.
  def show
    authorize @user, :show?
    load_status_panel
  end

  # Fallback when the phone system can't be trusted: set an agent's status by hand (audited).
  def override_status
    authorize @user, :override_status?, policy_class: BoardPolicy
    status = policy_scope(Status).active.find(params[:status_id])
    before = @user.current_status
    result = StatusEvents::Recorder.call(user: @user, status: status, at: Time.current, source: "manual")
    AuditLog.record!(current_user, "status_override", @user, "status" => [ before&.name, status.name ])
    redirect_to agent_path(@user), notice: "#{@user.full_name} is now #{status.name}."
  end

  def new
    @user = User.new(role: "agent", organization: current_user.organization, team_id: params[:team_id])
    authorize @user, :create?
    load_form_options
  end

  def create
    @user = User.new(user_params.merge(organization: current_user.organization))
    assign_requested_role
    clear_team_unless_agent
    authorize @user, :create?
    authorize @user, :assign_role?
    if @user.save
      AuditLog.record!(current_user, "created", @user, AuditLog.diff(@user).slice("role", "team_id", "phone_agent_id", "email_address"))
      Board::Broadcaster.roster_changed(current_user.organization, @user.team)
      redirect_to agents_path(role: @user.role), notice: "#{@user.full_name} added."
    else
      load_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @user, :update?
    load_form_options
  end

  def update
    authorize @user, :update?
    previous_team = @user.team
    @user.assign_attributes(user_params.except(:password))
    @user.password = user_params[:password] if user_params[:password].present?
    assign_requested_role
    clear_team_unless_agent
    authorize @user, :assign_role?
    authorize @user, :move_team? if @user.team_id_changed?
    if @user.save
      log_update(previous_team)
      Board::Broadcaster.roster_changed(current_user.organization, previous_team, @user.team)
      redirect_to agents_path(role: @user.role), notice: "#{@user.full_name} saved."
    else
      load_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def deactivate
    authorize @user, :destroy?
    @user.update!(active: false)
    AuditLog.record!(current_user, "deactivated", @user)
    Board::Broadcaster.roster_changed(current_user.organization, @user.team)
    redirect_back_or_to agents_path, notice: "#{@user.full_name} deactivated. They can no longer sign in."
  end

  def reactivate
    authorize @user, :update?
    @user.update!(active: true)
    AuditLog.record!(current_user, "reactivated", @user)
    Board::Broadcaster.roster_changed(current_user.organization, @user.team)
    redirect_back_or_to agents_path, notice: "#{@user.full_name} reactivated."
  end

  # Paste a list of agents (one per line): first, last, email, phone ID.
  def bulk_new
    authorize User, :create?
    @teams = policy_scope(Team).order(:name)
  end

  def bulk_create
    authorize User, :create?
    @teams = policy_scope(Team).order(:name)
    team = @teams.find_by(id: params[:team_id])
    @list = params[:list].to_s
    @errors, rows = parse_bulk_list(@list, team)

    if @errors.empty?
      @created = []
      User.transaction do
        rows.each do |attrs|
          password = SecureRandom.alphanumeric(10, chars: [ *"a".."k", *"m".."z", *"A".."H", *"J".."N", *"P".."Z", *"2".."9" ]) # no look-alike characters
          user = User.new(attrs.merge(organization: current_user.organization, team: team, role: "agent", password: password))
          unless user.save
            @errors << "#{attrs[:first_name]} #{attrs[:last_name]}: #{user.errors.full_messages.to_sentence}"
            raise ActiveRecord::Rollback
          end
          @created << [ user, password ]
        end
      end
    end

    if @errors.empty? && @created.present?
      AuditLog.record!(current_user, "bulk_created", team, "count" => @created.size, "agents" => @created.map { |u, _| u.full_name })
      Board::Broadcaster.roster_changed(current_user.organization, team)
      render :bulk_created # passwords are shown here once and never stored in readable form
    else
      @errors << "Nothing to add. Paste at least one line." if @list.strip.blank?
      render :bulk_new, status: :unprocessable_entity
    end
  end

  # Move the ticked agents to another team.
  def bulk_move
    authorize User, :index?
    team = policy_scope(Team).find(params[:team_id])
    authorize team, :update?
    users = policy_scope(User).where(id: Array(params[:ids]), role: "agent").includes(:team).to_a
    return redirect_back_or_to(agents_path, alert: "Tick at least one agent first.") if users.empty?
    previous_teams = users.map(&:team)
    User.transaction do
      users.each do |u|
        authorize u, :move_team?
        from = u.team
        next if from == team
        u.update!(team: team)
        AuditLog.record!(current_user, "moved_team", u, "team" => [ from&.name, team.name ])
      end
    end
    Board::Broadcaster.roster_changed(current_user.organization, team, previous_teams)
    redirect_back_or_to agents_path, notice: "Moved #{users.size} #{'agent'.pluralize(users.size)} to #{team.name}."
  end

  private

  # Everyone may open their own page (show); the other screens are for managers and up.
  def set_user
    authorize User, :index? unless action_name == "show"
    @user = policy_scope(User).find(params[:id])
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email_address, :phone_agent_id, :team_id, :password)
  end

  # The role is set on its own (never mass-assigned). An unknown value is refused outright; a
  # known one still has to pass UserPolicy#assign_role? (admins can't hand out admin).
  def assign_requested_role
    role = params.dig(:user, :role)
    return if role.blank?
    raise Pundit::NotAuthorizedError, "Unknown role" unless User::ROLES.include?(role)
    @user.role = role
  end

  # Only agents belong to a team. Managers get theirs from Team access.
  def clear_team_unless_agent
    @user.team = nil unless @user.agent?
  end

  def load_status_panel
    @current_event = @user.current_status_event
    @run_started_at = Board::Snapshot.rows_for([ @user ]).first.run_started_at
    start_of_day = Time.zone.now.beginning_of_day
    @todays_events = @user.status_events.includes(:status).overlapping(start_of_day, start_of_day + 1.day).in_order
    @can_override = BoardPolicy.new(current_user, @user).override_status?
    @override_statuses = policy_scope(Status).active.ordered if @can_override
  end

  def load_form_options
    @teams = policy_scope(Team).order(:name)
    @assignable_roles = policy(@user).assignable_roles
  end

  def log_update(previous_team)
    changes = AuditLog.diff(@user).except("team_id")
    AuditLog.record!(current_user, "updated", @user, changes) if changes.any?
    AuditLog.record!(current_user, "moved_team", @user, "team" => [ previous_team&.name, @user.team&.name ]) if previous_team != @user.team
    AuditLog.record!(current_user, "password_reset", @user) if user_params[:password].present?
  end

  # Returns [error messages, rows]. Each line: first, last, email, phone ID (optional).
  def parse_bulk_list(text, team)
    errors = []
    rows = []
    errors << "Choose a team." if team.nil?
    text.lines.map(&:strip).reject(&:blank?).each_with_index do |line, i|
      first, last, email, phone = line.split(line.include?("\t") ? "\t" : ",").map(&:strip)
      if first.blank? || last.blank? || email.blank?
        errors << "Line #{i + 1}: needs first name, last name and email (“#{line.truncate(40)}”)."
      else
        rows << { first_name: first, last_name: last, email_address: email, phone_agent_id: phone }
      end
    end
    [ errors, rows ]
  end
end
