require "test_helper"
require "turbo/broadcastable/test_helper"

class BoardBroadcastTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper
  include ActionCable::TestHelper

  NOW = Time.utc(2026, 11, 3, 20, 0, 0)

  setup do
    travel_to NOW
    @user = users(:agent_a1)
  end

  def record(status, user: @user, at: NOW - 1.minute, id: nil)
    StatusEvents::Recorder.call(user: user, status: statuses(status), at: at, source: "phone", external_event_id: id)
  end

  test "a status change replaces that agent's row on the organization board and their team's board" do
    assert_turbo_stream_broadcasts([ organizations(:summit), :board ], count: 1) do
      assert_turbo_stream_broadcasts([ teams(:team_a), :board ], count: 1) do
        record(:on_call)
      end
    end
    streams = capture_turbo_stream_broadcasts([ teams(:team_a), :board ])
    stream = streams.first
    assert_equal "replace", stream["action"]
    assert_equal "board_row_user_#{@user.id}", stream["target"]
    assert_includes stream.to_html, "On Call"
    assert_includes stream.to_html, @user.full_name
  end

  test "the replacement row carries the live-timer and bar data" do
    record(:break)
    html = capture_turbo_stream_broadcasts([ teams(:team_a), :board ]).first.to_html
    assert_includes html, "data-elapsed-since=\"#{((NOW - 1.minute).to_f * 1000).to_i}\""
    assert_includes html, "data-limit-seconds=\"900\""
    assert_includes html, "data-events="
  end

  test "other teams' boards hear nothing" do
    assert_no_turbo_stream_broadcasts([ teams(:team_b), :board ]) { record(:on_call) }
    assert_no_turbo_stream_broadcasts([ organizations(:other), :board ]) { record(:on_call, id: "x") }
  end

  test "an agent's own page is refreshed" do
    assert_turbo_stream_broadcasts([ @user, :status ], count: 1) { record(:on_call) }
  end

  test "an agent with no team still shows up on the organization board" do
    users(:agent_a1).update_columns(team_id: nil)
    assert_turbo_stream_broadcasts([ organizations(:summit), :board ], count: 1) { record(:on_call) }
  end

  test "a retry (duplicate) doesn't broadcast again" do
    record(:on_call, id: "e1")
    stream = [ organizations(:summit), :board ]
    before = capture_turbo_stream_broadcasts(stream).size
    assert_equal :duplicate, record(:on_call, id: "e1").outcome
    assert_equal before, capture_turbo_stream_broadcasts(stream).size
  end

  test "the webhook, a manual override and the simulator's path all broadcast" do
    key = organizations(:summit).generate_api_key!
    assert_turbo_stream_broadcasts([ organizations(:summit), :board ], count: 1) do
      post api_v1_status_events_path, params: { agent_id: "A1001", status_code: "InCall", occurred_at: (NOW - 1.minute).iso8601, event_id: "w1" }.to_json,
           headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{key}" }
    end
    sign_in_as manager
    assert_turbo_stream_broadcasts([ organizations(:summit), :board ], count: 1) do
      post override_status_agent_path(@user), params: { status_id: statuses(:break).id }
    end
  end

  test "deactivated agents are not broadcast" do
    @user.update!(active: false)
    assert_no_turbo_stream_broadcasts([ organizations(:summit), :board ]) { record(:on_call) }
  end

  test "a broadcast problem never loses the event" do
    original = Turbo::StreamsChannel.method(:broadcast_replace_to)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to) { |*, **| raise "cable is down" }
    begin
      result = record(:on_call)
      assert_equal :recorded, result.outcome
      assert_equal statuses(:on_call), @user.reload.current_status
    ensure
      Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to, original)
    end
  end

  test "roster changes ask the affected boards to reload" do
    sign_in_as admin
    assert_turbo_stream_broadcasts([ organizations(:summit), :board ]) do
      assert_turbo_stream_broadcasts([ teams(:team_a), :board ]) do
        assert_turbo_stream_broadcasts([ teams(:team_c), :board ]) do
          patch agent_path(@user), params: { user: { team_id: teams(:team_c).id } }
        end
      end
    end
    assert_equal "refresh", capture_turbo_stream_broadcasts([ teams(:team_c), :board ]).last["action"]
  end

  test "deactivating, adding and renaming also refresh the board" do
    sign_in_as admin
    assert_turbo_stream_broadcasts([ teams(:team_a), :board ]) { patch deactivate_agent_path(@user) }
    assert_turbo_stream_broadcasts([ teams(:team_a), :board ]) { patch team_path(teams(:team_a)), params: { team: { name: "Sales Alpha" } } }
    assert_turbo_stream_broadcasts([ teams(:team_b), :board ]) do
      post agents_path, params: { user: { first_name: "Nia", last_name: "New", email_address: "nia@example.com", team_id: teams(:team_b).id, role: "agent", password: "temp-pass-123" } }
    end
  end
end
