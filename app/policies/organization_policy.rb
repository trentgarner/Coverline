# Organization-wide settings. Headless (authorize :organization, :manage_settings?).
class OrganizationPolicy < ApplicationPolicy
  # Settings -> Targets: TST/CFT targets and grace periods (plan sections 6 and 7).
  def update_targets? = user.admin_or_above?

  # Org name/timezone, who the admins are, and the phone-system integration.
  def manage_settings? = user.super_user?
  def manage_admins? = user.super_user?
  def manage_integration? = user.super_user?
end
