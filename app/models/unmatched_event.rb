# A phone event that needs an admin's attention (see the migration for the two reasons).
class UnmatchedEvent < ApplicationRecord
  REASONS = %w[unknown_agent unmapped_code].freeze

  belongs_to :organization

  validates :reason, inclusion: { in: REASONS }

  scope :unresolved, -> { where(resolved_at: nil) }
  scope :unknown_agents, -> { where(reason: "unknown_agent") }
  scope :unmapped_codes, -> { where(reason: "unmapped_code") }

  def resolve! = update!(resolved_at: Time.current)
end
