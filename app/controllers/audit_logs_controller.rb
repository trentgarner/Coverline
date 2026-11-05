class AuditLogsController < ApplicationController
  PER_PAGE = 50
  after_action :verify_policy_scoped, only: :index

  def index
    authorize :audit_log, :index?
    logs = policy_scope(AuditLog).includes(:user).newest_first
    logs = logs.where(user_id: params[:user_id]) if params[:user_id].present?
    logs = logs.where(action: params[:action_name]) if params[:action_name].present?
    @page = [ params[:page].to_i, 1 ].max
    @has_more = logs.offset(@page * PER_PAGE).exists?
    @logs = logs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @actors = User.where(id: policy_scope(AuditLog).select(:user_id)).order(:last_name, :first_name)
    @actions = policy_scope(AuditLog).distinct.order(:action).pluck(:action)
  end
end
