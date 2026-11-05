class Team < ApplicationRecord
  belongs_to :organization
  has_many :users, dependent: :nullify
  has_many :team_accesses, dependent: :destroy
  has_many :managers, through: :team_accesses, source: :user

  validates :name, presence: true, uniqueness: { scope: :organization_id }
end
