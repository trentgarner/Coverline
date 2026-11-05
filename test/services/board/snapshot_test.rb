require "test_helper"

class SnapshotTest < ActiveSupport::TestCase
  # 2:00 PM in Chicago (CST, UTC-6 after the Nov 1 change) on Nov 3, 2026
  NOW = Time.utc(2026, 11, 3, 20, 0, 0)

  setup do
    travel_to NOW
    @user = users(:agent_a1)
  end

  def put(status, at, id = SecureRandom.uuid)
    StatusEvents::Recorder.call(user: @user, status: statuses(status), at: at, source: "phone", external_event_id: id)
  end

  def row(user = @user) = Time.use_zone("America/Chicago") { Board::Snapshot.rows_for([ user ], now: NOW).first }

  test "an agent with no events gets an empty row" do
    r = row
    assert_nil r.status
    assert_nil r.run_started_at
    assert_nil r.logged_in_at
    assert_empty r.events
    assert_not r.current?
  end

  test "current status, run start, and first login" do
    put(:offline, NOW - 10.hours)         # 10:00 AM, still logged out
    put(:available, NOW - 5.hours)        # 9:00 AM logs in
    put(:on_call, NOW - 4.hours)
    put(:available, NOW - 1.hour)
    r = row
    assert_equal statuses(:available), r.status
    assert_equal NOW - 1.hour, r.run_started_at
    assert_equal NOW - 5.hours, r.logged_in_at, "first non-offline status today"
    assert_equal 4, r.events.size
    assert r.current?
  end

  test "consecutive events with the same status count as one run" do
    put(:available, NOW - 3.hours)
    put(:available, NOW - 2.hours)
    put(:available, NOW - 1.hour)
    assert_equal NOW - 3.hours, row.run_started_at
    put(:on_call, NOW - 30.minutes)
    assert_equal NOW - 30.minutes, row.run_started_at
    put(:available, NOW - 10.minutes)
    assert_equal NOW - 10.minutes, row.run_started_at, "a different status in between starts a new run"
  end

  test "only today's events are listed, using the organization's time zone for midnight" do
    put(:available, Time.utc(2026, 11, 3, 5, 0, 0))  # 11:00 PM Nov 2 in Chicago: yesterday
    put(:on_call, Time.utc(2026, 11, 3, 7, 0, 0))    # 1:00 AM Nov 3 in Chicago: today
    r = row
    assert_equal [ "Available", "On Call" ], r.events.map { |e| e.status.name }, "the one running across midnight still counts as today"
    assert_equal Time.utc(2026, 11, 3, 5, 0, 0), r.logged_in_at

    @user.status_events.delete_all
    put(:available, Time.utc(2026, 11, 3, 5, 0, 0))
    put(:offline, Time.utc(2026, 11, 3, 5, 30, 0))   # closed before midnight Chicago (06:00 UTC)
    put(:on_call, Time.utc(2026, 11, 3, 14, 0, 0))   # 8:00 AM today
    r = row
    assert_equal [ "Offline", "On Call" ], r.events.map { |e| e.status.name }, "events that ended before midnight are left out"
  end

  test "logging in means leaving the offline category" do
    put(:offline, NOW - 6.hours)
    assert_nil row.logged_in_at
    put(:break, NOW - 2.hours)
    assert_equal NOW - 2.hours, row.logged_in_at
  end

  test "many agents are loaded with one events query" do
    put(:available, NOW - 1.hour)
    users = [ @user, users(:agent_a2), users(:agent_b1), users(:agent_c1) ]
    queries = 0
    counter = ->(*, payload) { queries += 1 if payload[:sql] =~ /FROM "status_events"/ }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { Board::Snapshot.rows_for(users, now: NOW) }
    assert_equal 1, queries
  end

  test "results line up with the users given, in order" do
    rows = Board::Snapshot.rows_for([ users(:agent_b1), @user ], now: NOW)
    assert_equal [ users(:agent_b1), @user ], rows.map(&:user)
  end
end
