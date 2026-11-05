require "test_helper"

class RecorderTest < ActiveSupport::TestCase
  BASE = Time.utc(2026, 11, 1, 15, 0, 0)

  setup do
    travel_to BASE + 4.hours # "now" is well after every event below
    @user = users(:agent_a1)
    @available, @on_call, @break, @offline = statuses(:available), statuses(:on_call), statuses(:break), statuses(:offline)
  end

  def record(status, minutes, id: nil, user: @user, source: "phone")
    StatusEvents::Recorder.call(user: user, status: status, at: BASE + minutes.minutes, source: source, external_event_id: id)
  end

  test "the first event opens the timeline" do
    result = record(@available, 0, id: "e1")
    assert_equal :recorded, result.outcome
    assert_equal [ [ "Available", BASE, nil ] ], timeline_of(@user)
    assert_equal @available, @user.reload.current_status
  end

  test "each new event closes the previous one at the same instant" do
    record(@available, 0)
    record(@on_call, 10)
    record(@break, 25)
    assert_equal [ [ "Available", BASE, BASE + 10.minutes ], [ "On Call", BASE + 10.minutes, BASE + 25.minutes ], [ "Break", BASE + 25.minutes, nil ] ], timeline_of(@user)
    assert_equal @break, @user.reload.current_status
    assert_timeline_consistent(@user)
  end

  test "retrying an event id changes nothing" do
    first = record(@available, 0, id: "e1")
    record(@on_call, 10, id: "e2")
    again = record(@available, 0, id: "e1")
    assert_equal :duplicate, again.outcome
    assert_equal first.event, again.event
    assert_equal 2, @user.status_events.count
    assert_equal "On Call", @user.reload.current_status.name, "a late retry doesn't undo newer events"
    assert_equal :duplicate, record(@on_call, 10, id: "e2").outcome
  end

  test "an event with no id (a manual change) is never treated as a duplicate" do
    record(@available, 0)
    assert_equal :recorded, record(@on_call, 5, source: "manual").outcome
    assert_equal :recorded, record(@available, 6, source: "manual").outcome
    assert_equal 3, @user.status_events.count
  end

  test "the same status twice is still recorded (order-safe), and the timeline stays consistent" do
    record(@available, 0, id: "a")
    record(@available, 5, id: "b")
    assert_equal 2, @user.status_events.count
    assert_timeline_consistent(@user)
  end

  test "an event that arrives late slots into the middle of the timeline" do
    record(@available, 0, id: "e1")
    record(@break, 30, id: "e3")
    record(@on_call, 10, id: "e2") # arrives after e3 but happened before it
    assert_equal [ [ "Available", BASE, BASE + 10.minutes ], [ "On Call", BASE + 10.minutes, BASE + 30.minutes ], [ "Break", BASE + 30.minutes, nil ] ], timeline_of(@user)
    assert_timeline_consistent(@user)
  end

  test "an event older than everything becomes the first, and the current status is untouched" do
    record(@on_call, 20, id: "e2")
    record(@available, 0, id: "e1")
    assert_equal [ [ "Available", BASE, BASE + 20.minutes ], [ "On Call", BASE + 20.minutes, nil ] ], timeline_of(@user)
    assert_equal @on_call, @user.reload.current_status
  end

  test "two events at the same instant don't break anything" do
    record(@available, 0, id: "a")
    record(@on_call, 0, id: "b")
    assert_timeline_consistent(@user)
    assert_equal 2, @user.status_events.count
  end

  test "agents have separate timelines" do
    other = users(:agent_a2)
    record(@available, 0)
    record(@break, 5, user: other)
    assert_equal @available, @user.reload.current_status
    assert_equal @break, other.reload.current_status
  end

  test "a time in the future is refused, a few minutes of clock drift is allowed" do
    now = Time.current
    assert_raises(StatusEvents::Recorder::InvalidTime) do
      StatusEvents::Recorder.call(user: @user, status: @available, at: now + 10.minutes, source: "phone")
    end
    assert_equal :recorded, StatusEvents::Recorder.call(user: @user, status: @available, at: now + 2.minutes, source: "phone").outcome
    assert_equal 1, @user.status_events.count
  end

  test "the database itself refuses a second open event for one agent" do
    record(@available, 0)
    assert_raises(ActiveRecord::RecordNotUnique) do
      StatusEvent.insert_all!([ { user_id: @user.id, status_id: @break.id, started_at: BASE + 5.minutes, source: "phone", created_at: Time.current, updated_at: Time.current } ])
    end
  end

  test "an event can't end before it starts" do
    event = record(@available, 0).event
    event.ended_at = BASE - 1.minute
    assert_not event.valid?
  end

  # The guarantee that matters: however events are reordered or re-sent, the result is the same.
  test "shuffled and duplicated delivery gives exactly the same timeline as in-order delivery" do
    rng = Random.new(2026)
    cycle = [ @available, @on_call, @break, @available, @on_call, @offline ]
    5.times do |round|
      stream = (0...40).map { |i| { id: "r#{round}-#{i}", status: cycle[(i + round) % cycle.size], at: i * 3 } } # distinct times
      ordered_user = users(:agent_a1)
      shuffled_user = users(:agent_a2)
      [ ordered_user, shuffled_user ].each { |u| u.status_events.delete_all }

      stream.each { |e| record(e[:status], e[:at], id: "o-#{e[:id]}", user: ordered_user) }
      deliveries = (stream + stream.sample(15, random: rng)).shuffle(random: rng) # re-sends too
      deliveries.each { |e| record(e[:status], e[:at], id: "s-#{e[:id]}", user: shuffled_user) }

      assert_equal timeline_of(ordered_user), timeline_of(shuffled_user), "round #{round}"
      assert_equal 40, shuffled_user.status_events.count, "re-sends added nothing"
      assert_timeline_consistent(shuffled_user)
    end
  end
end
