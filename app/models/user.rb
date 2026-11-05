class User < ApplicationRecord
  ROLES = %w[agent manager admin super_user].freeze

  has_secure_password
  has_many :sessions, dependent: :destroy
  belongs_to :organization
  belongs_to :team, optional: true
  has_many :team_accesses, dependent: :destroy
  has_many :accessible_teams, through: :team_accesses, source: :team
  has_many :status_events, dependent: :destroy
  has_one :current_status_event, -> { where(ended_at: nil) }, class_name: "StatusEvent"

  enum :role, ROLES.index_with(&:itself), default: "agent"

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :phone_agent_id, with: ->(v) { v.presence&.strip }

  validates :first_name, :last_name, presence: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :phone_agent_id, uniqueness: { scope: :organization_id }, allow_nil: true
  validate :team_in_same_organization

  scope :active, -> { where(active: true) }

  def current_status = current_status_event&.status

  def full_name = "#{first_name} #{last_name}"

  # Role checks used by the policies. Each role includes everything below it.
  def at_least?(role) = ROLES.index(self.role) >= ROLES.index(role.to_s)
  def admin_or_above? = at_least?(:admin)

  # The teams this person may see on the board: all of them for admins and up,
  # their granted teams for managers, none for agents.
  def visible_teams
    return Team.where(organization_id: organization_id) if admin_or_above?
    return accessible_teams if manager?
    Team.none
  end

  private

  def team_in_same_organization
    errors.add(:team, "must be in the same organization") if team && team.organization_id != organization_id
  end
end
