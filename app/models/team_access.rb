# Join between a manager and a team they may see. Table is named team_access.
class TeamAccess < ApplicationRecord
  self.table_name = "team_access"

  belongs_to :user
  belongs_to :team

  validates :team_id, uniqueness: { scope: :user_id }
  validate :user_is_a_manager
  validate :same_organization

  private

  def user_is_a_manager
    errors.add(:user, "must be a manager") unless user&.manager?
  end

  def same_organization
    errors.add(:team, "must be in the manager's organization") if user && team && user.organization_id != team.organization_id
  end
end
