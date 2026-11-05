# One row per status change for one agent. The row with no ended_at is their current status.
# Rows are written only through StatusEvents::Recorder, which keeps the timeline consistent.
class StatusEvent < ApplicationRecord
  SOURCES = %w[phone manual simulator].freeze

  belongs_to :user
  belongs_to :status

  validates :started_at, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :external_event_id, uniqueness: true, allow_nil: true
  validate :ends_after_it_starts

  scope :current, -> { where(ended_at: nil) }
  scope :in_order, -> { order(:started_at, :id) }
  # Events overlapping the given span (used for "today" views).
  scope :overlapping, ->(from, to) { where("started_at < ? AND (ended_at IS NULL OR ended_at > ?)", to, from) }

  def current? = ended_at.nil?

  # Length so far (or total, once closed).
  def duration(now = Time.current) = (ended_at || now) - started_at

  private

  def ends_after_it_starts
    errors.add(:ended_at, "can't be before the start") if ended_at && started_at && ended_at < started_at
  end
end
