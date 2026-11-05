module StatusEvents
  # The one place status changes are written. Whatever order events arrive in (retries and
  # network delays reorder things), the agent's timeline ends up the same: events sorted by
  # time, each one ending exactly when the next begins, and only the latest one left open.
  class Recorder
    class InvalidTime < StandardError; end

    Result = Struct.new(:outcome, :event, keyword_init: true) # outcome: :recorded or :duplicate

    # A phone clock that runs a little fast is tolerated; beyond this we refuse the event.
    FUTURE_TOLERANCE = 5.minutes

    def self.call(**args) = new(**args).call

    def initialize(user:, status:, at:, source:, external_event_id: nil)
      @user = user
      @status = status
      @at = at
      @source = source
      @external_event_id = external_event_id.presence
    end

    def call
      raise InvalidTime, "that time is in the future" if @at > Time.current + FUTURE_TOLERANCE

      result = StatusEvent.transaction do
        @user.lock! # one agent's events are processed one at a time
        existing = @external_event_id && StatusEvent.find_by(external_event_id: @external_event_id)
        return Result.new(outcome: :duplicate, event: existing) if existing

        events = @user.status_events
        previous = events.where("started_at <= ?", @at).order(started_at: :desc, id: :desc).first
        following = events.where("started_at > ?", @at).order(:started_at, :id).first

        previous&.update!(ended_at: @at) # close what was in effect, then open the new one
        event = events.create!(status: @status, started_at: @at, ended_at: following&.started_at,
                               source: @source, external_event_id: @external_event_id)
        Result.new(outcome: :recorded, event: event)
      end
      Board::Broadcaster.status_changed(@user) if result.outcome == :recorded
      result
    end
  end
end
