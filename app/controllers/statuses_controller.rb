class StatusesController < ApplicationController
  before_action :set_status, only: %i[edit update]
  after_action :verify_policy_scoped, only: :index

  def index
    authorize Status, :manage?
    @statuses = policy_scope(Status).ordered.includes(:status_codes)
    @unmapped_codes = current_user.organization.unmatched_events.unmapped_codes.unresolved.group(:phone_code).count
  end

  def new
    @status = Status.new({ organization: current_user.organization, color: "#2f9e6f", category: "other" }.merge(Status.flag_defaults_for("other")))
    authorize @status, :create?
  end

  def create
    @status = Status.new(status_params.merge(organization: current_user.organization))
    authorize @status, :create?
    @status.sort_order = (policy_scope(Status).maximum(:sort_order) || 0) + 1
    if @status.save_with_codes
      AuditLog.record!(current_user, "created", @status, "phone_codes" => @status.phone_code_list)
      redirect_to statuses_path, notice: "#{@status.name} added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @status, :update?
  end

  def update
    authorize @status, :update?
    previous_codes = @status.status_codes.map(&:phone_code).sort
    @status.assign_attributes(status_params)
    if @status.save_with_codes
      changes = AuditLog.diff(@status)
      codes = @status.phone_code_list.sort
      changes["phone_codes"] = [ previous_codes, codes ] if @status.phone_codes_text && previous_codes != codes
      AuditLog.record!(current_user, "updated", @status, changes) if changes.any?
      redirect_to statuses_path, notice: "#{@status.name} saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Drag-to-reorder: the page sends the full list of status ids in their new order.
  def reorder
    authorize Status, :reorder?
    ids = Array(params[:ids]).map(&:to_i)
    statuses = policy_scope(Status).where(id: ids).index_by(&:id)
    Status.transaction do
      ids.each_with_index { |id, i| statuses[id]&.update!(sort_order: i + 1) }
    end
    AuditLog.record!(current_user, "reordered", statuses.values.first, "order" => ids.filter_map { |id| statuses[id]&.name }) if statuses.any?
    head :no_content
  end

  private

  def set_status = (@status = policy_scope(Status).find(params[:id]))

  def status_params
    params.require(:status).permit(:name, :color, :category, :productive, :counts_toward_cft, :active, :time_limit_minutes, :phone_codes_text)
  end
end
