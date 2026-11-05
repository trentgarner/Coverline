require "test_helper"
require "status_simulator"

class StatusSimulatorTest < ActiveSupport::TestCase
  CODES = { "Available" => "Ready", "On Call" => "InCall", "Break" => "AUX-2", "Offline" => "LOGGEDOUT" }.freeze

  def sim(ids = %w[A1001 A1002 A1003], seed: 1) = StatusSimulator.new(phone_ids: ids, codes: CODES, random: Random.new(seed))

  test "every move is a legal step for that agent's current status, with a unique event id" do
    s = sim
    seen = Set.new
    allowed = StatusSimulator::TRANSITIONS
    200.times do
      before = s.agents.to_h { |a| [ a.phone_id, a.state ] }
      s.step(count: 2).each do |event|
        agent = s.agents.find { |a| a.phone_id == event[:agent_id] }
        assert_includes allowed.fetch(before[agent.phone_id]).map(&:first), agent.state
        assert_equal CODES.fetch(agent.state), event[:status_code]
        assert seen.add?(event[:event_id]), "duplicate event id"
        assert_match(/\Asim-/, event[:event_id])
        assert Time.iso8601(event[:occurred_at])
      end
    end
  end

  test "agents begin offline and the first moves log them in" do
    s = sim
    assert s.agents.all? { |a| a.state == "Offline" }
    events = s.step(count: 3)
    assert_equal %w[Ready Ready Ready], events.map { |e| e[:status_code] }
  end

  test "statuses with no phone code are never used" do
    s = StatusSimulator.new(phone_ids: %w[A1], codes: { "Available" => "Ready", "On Call" => "InCall" }, random: Random.new(3))
    codes = 100.times.flat_map { s.step(count: 1) }.map { |e| e[:status_code] }.uniq
    assert_empty codes - %w[Ready InCall]
  end

  test "the same seed gives the same story" do
    a = sim(seed: 9).step(count: 3).map { |e| e.slice(:agent_id, :status_code) }
    b = sim(seed: 9).step(count: 3).map { |e| e.slice(:agent_id, :status_code) }
    assert_equal a, b
  end

  # The Phase 3 "done when", end to end: simulated events through the real pipeline.
  test "hundreds of simulated events leave clean timelines with no duplicates" do
    travel_to Time.utc(2026, 11, 1, 20, 0, 0)
    ids = %w[A1001 A1002 B1001 C1001]
    s = StatusSimulator.new(phone_ids: ids, codes: { "Available" => "Ready", "On Call" => "InCall", "Break" => "AUX-2", "Offline" => "LOGGEDOUT" }, random: Random.new(11))
    ingest = StatusEvents::Ingest.new(organizations(:summit))
    sent = []
    clock = Time.utc(2026, 11, 1, 14, 0, 0)
    400.times do
      clock += 7.seconds
      s.step(count: 2, now: clock).each { |e| sent << e }
    end

    # Deliver in order, then deliver the whole thing again shuffled (a retry storm).
    results = sent.map { |e| ingest.call(e.transform_keys(&:to_s)) }
    assert results.all? { |r| r.outcome == :recorded }, results.map(&:outcome).tally.inspect
    expected_rows = StatusEvent.count
    assert_equal sent.size, expected_rows, "one row per event"
    sent.shuffle(random: Random.new(5)).each { |e| assert_equal :duplicate, ingest.call(e.transform_keys(&:to_s)).outcome }
    assert_equal expected_rows, StatusEvent.count, "retries added nothing"

    User.where(phone_agent_id: ids).each { |u| assert_timeline_consistent(u) }
    assert_equal 4, StatusEvent.current.count, "exactly one open event per agent"
    assert_equal StatusEvent.count, StatusEvent.where.not(external_event_id: nil).distinct.count(:external_event_id)
  end
end
