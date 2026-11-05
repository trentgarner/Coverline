class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user

  # Every action must authorize (index actions must also use policy_scope).
  after_action :verify_authorized

  around_action :use_organization_time_zone

  rescue_from Pundit::NotAuthorizedError, with: :not_authorized

  private

  def current_user = Current.user
  def pundit_user = Current.user

  def use_organization_time_zone(&block)
    zone = current_user&.organization&.timezone
    zone ? Time.use_zone(zone, &block) : yield
  end

  def not_authorized
    redirect_back_or_to root_path, alert: "You don't have access to that.", status: :see_other
  end
end
