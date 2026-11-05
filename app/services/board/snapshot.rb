module Board
  # Everything one board row needs, computed for many agents with a single query.
  # Times are real instants; the page shows them in the organization's time zone.
  class Snapshot
    # How far back we look for an agent's current "run" of one status. Long enough that an
    # overnight Offline reads right; a run older than this simply measures from the window.
    WINDOW = 36.hours

    Row = Struct.new(:user, :event, :status, :run_started_at, :logged_in_at, :events, keyword_init: true) do
      def current? = event.present?
    end

    # users: the agents to show. Returns one Row per user (agents with no events get an empty row).
    def self.rows_for(users, now: Time.current)
      users = users.to_a
      zone = users.first&.organization&.timezone || "UTC"
      start_of_day = now.in_time_zone(zone).beginning_of_day
      events = StatusEvent.where(user_id: users.map(&:id)).overlapping(now - WINDOW, now + 1.minute)
                          .includes(:status).in_order.group_by(&:user_id)

      users.map do |user|
        mine = events[user.id] || []
        current = mine.last if mine.last&.ended_at.nil?
        today = mine.select { |e| e.ended_at.nil? || e.ended_at > start_of_day }
        Row.new(user: user, event: current, status: current&.status, run_started_at: run_start(mine, current),
                logged_in_at: today.find { |e| e.status.category != "offline" }&.started_at, events: today)
      end
    end

    # When did the current run of this status begin? (Contiguous events with the same status count as one run.)
    def self.run_start(events, current)
      return nil unless current
      start = current.started_at
      events.reverse.drop(1).each do |earlier|
        break unless earlier.status_id == current.status_id
        start = earlier.started_at
      end
      start
    end
  end
end
