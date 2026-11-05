require "test_helper"

class IngestTest < ActiveSupport::TestCase
  setup do
    travel_to Time.utc(2026, 11, 1, 20, 0, 0)
    @org = organizations(:summit)
    @ingest = StatusEvents::Ingest.new(@org)
    @user = users(:agent_a1) # phone ID A1001
  end

  def event(overrides = {})
    { "agent_id" => "A1001", "status_code" => "Ready", "occurred_at" => "2026-11-01T15:00:00Z", "event_id" => "evt-1" }.merge(overrides)
  end

  test "a mapped code records the agent's new status" do
    result = @ingest.call(event)
    assert_equal :recorded, result.outcome
    assert_equal "evt-1", result.event_id
    e = @user.status_events.last
    assert_equal [ "Available", "phone", "evt-1", Time.utc(2026, 11, 1, 15) ], [ e.status.name, e.source, e.external_event_id, e.started_at ]
    assert_equal statuses(:available), @user.reload.current_status
  end

  test "codes match regardless of case, and several codes can mean one status" do
    @ingest.call(event("status_code" => "aux-2", "event_id" => "e1"))
    assert_equal "Break", @user.reload.current_status.name
    @ingest.call(event("status_code" => "BREAK", "occurred_at" => "2026-11-01T15:05:00Z", "event_id" => "e2"))
    assert_equal [ "Break", "Break" ], @user.status_events.in_order.map { |x| x.status.name }
  end

  test "the same event sent twice is recorded once" do
    assert_equal :recorded, @ingest.call(event).outcome
    assert_equal :duplicate, @ingest.call(event).outcome
    assert_equal 1, @user.status_events.count
  end

  test "times with offsets are understood" do
    @ingest.call(event("occurred_at" => "2026-11-01T10:00:00-05:00"))
    assert_equal Time.utc(2026, 11, 1, 15), @user.status_events.last.started_at
  end

  test "an unmapped code is recorded as Unmapped, and noted once for an admin" do
    result = @ingest.call(event("status_code" => "AUX-9", "event_id" => "x1"))
    assert_equal :unmapped_code, result.outcome
    assert_match "AUX-9", result.detail
    assert_equal "Unmapped", @user.reload.current_status.name
    assert_equal @org.unmapped_status, @user.current_status
    note = @org.unmatched_events.unmapped_codes.sole
    assert_equal [ "AUX-9", "A1001", "x1", nil ], [ note.phone_code, note.phone_agent_id, note.external_event_id, note.resolved_at ]

    assert_equal :duplicate, @ingest.call(event("status_code" => "AUX-9", "event_id" => "x1")).outcome
    assert_equal 1, @org.unmatched_events.unmapped_codes.count, "a retry isn't counted twice"
  end

  test "the Unmapped status is created once, with a warning color, and reused" do
    assert_difference "Status.count", 1 do
      2.times { |i| @ingest.call(event("status_code" => "NOPE#{i}", "event_id" => "n#{i}", "occurred_at" => "2026-11-01T15:0#{i}:00Z")) }
    end
    s = @org.reload.unmapped_status
    assert_equal [ "Unmapped", "other", "#ffc107" ], [ s.name, s.category, s.color ]
  end

  test "a code that maps to a deactivated status counts as unmapped" do
    statuses(:break).update!(active: false)
    assert_equal :unmapped_code, @ingest.call(event("status_code" => "AUX-2")).outcome
  end

  test "an unknown agent ID is held, not recorded, and held only once" do
    result = @ingest.call(event("agent_id" => "ZZ999", "event_id" => "u1"))
    assert_equal :unknown_agent, result.outcome
    assert_equal 0, StatusEvent.count
    held = @org.unmatched_events.unknown_agents.sole
    assert_equal [ "ZZ999", "Ready", "u1" ], [ held.phone_agent_id, held.phone_code, held.external_event_id ]
    assert_equal({ "agent_id" => "ZZ999", "status_code" => "Ready", "occurred_at" => "2026-11-01T15:00:00Z", "event_id" => "u1" }, held.payload)
    @ingest.call(event("agent_id" => "ZZ999", "event_id" => "u1"))
    assert_equal 1, @org.unmatched_events.unknown_agents.count
  end

  test "a deactivated agent's events are ignored" do
    @user.update!(active: false)
    result = @ingest.call(event)
    assert_equal :inactive_agent, result.outcome
    assert_equal 0, StatusEvent.count
    assert_equal 0, @org.unmatched_events.count
  end

  test "agent IDs are looked up inside the organization only" do
    users(:other_agent).update!(phone_agent_id: "A1001") # same ID, different company
    @ingest.call(event)
    assert_equal 1, @user.status_events.count
    assert_equal 0, users(:other_agent).status_events.count
    other = StatusEvents::Ingest.new(organizations(:other)).call(event("event_id" => "evt-2"))
    assert_equal :recorded, other.outcome
    assert_equal 1, users(:other_agent).status_events.count
    assert_equal 1, @user.status_events.count
  end

  test "malformed events are refused with a reason" do
    {
      { "event_id" => "" } => /event_id is required/,
      { "agent_id" => "" } => /agent_id is required/,
      { "status_code" => "" } => /status_code is required/,
      { "occurred_at" => "yesterday" } => /ISO 8601/,
      { "occurred_at" => nil } => /ISO 8601/,
      { "occurred_at" => "2026-11-01T22:00:00Z" } => /future/
    }.each do |overrides, message|
      result = @ingest.call(event(overrides))
      assert_equal :invalid, result.outcome, overrides.inspect
      assert_match message, result.detail
    end
    assert_equal 0, StatusEvent.count
  end

  test "events for the same agent can arrive out of order" do
    @ingest.call(event("status_code" => "InCall", "occurred_at" => "2026-11-01T15:10:00Z", "event_id" => "b"))
    @ingest.call(event("status_code" => "Ready", "occurred_at" => "2026-11-01T15:00:00Z", "event_id" => "a"))
    assert_equal %w[Available On\ Call], @user.status_events.in_order.map { |e| e.status.name }
    assert_timeline_consistent(@user)
  end
end
