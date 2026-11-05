require "test_helper"

class BoardTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 11, 3, 20, 0, 0) # 2:00 PM Chicago

  setup do
    travel_to NOW
    put(users(:agent_a1), :on_call, NOW - 12.minutes)
    put(users(:agent_a2), :break, NOW - 20.minutes)
    put(users(:agent_b1), :available, NOW - 2.hours)
    put(users(:agent_c1), :offline, NOW - 5.hours)
  end

  def put(user, status, at) = StatusEvents::Recorder.call(user: user, status: statuses(status), at: at, source: "phone")

  def names_on_board = css_select("#board tr.board-row [href^='/agents/']").map(&:text)

  test "an admin sees every active agent in the organization, grouped by team" do
    sign_in_as admin
    get board_path
    assert_response :success
    assert_select "#board tr.board-row", 4 + 0 # a1 a2 b1 c1 (inactive agent hidden, other org hidden)
    assert_equal [ "Sales Team A", "Sales Team B", "Sales Team C" ], css_select("tr[data-team-header] th").map { |th| th.text.strip.sub(/\s+\d.*/, "") }
    assert_equal %w[Alex\ Agent Avery\ Agent Blake\ Agent Casey\ Agent], names_on_board
    assert_select "#board [href='#{agent_path(users(:inactive_agent))}']", false
    assert_select "#board [href='#{agent_path(users(:other_agent))}']", false
  end

  test "agents with no phone data yet still get a row" do
    sign_in_as admin
    get board_path
    assert_select "tr.board-row", 4
    sign_out
    users(:agent_b1).status_events.delete_all
    sign_in_as admin
    get board_path
    assert_select "tr[data-user-id='#{users(:agent_b1).id}'] .board-status", /No data yet/
  end

  test "each row shows the status pill in its color, the timer, login time and event data for the bar" do
    sign_in_as admin
    get board_path
    row = "tr[data-user-id='#{users(:agent_a1).id}']"
    assert_select "#{row} .board-status .badge[style*='#1f6fb2']", "On Call"
    assert_select "#{row} .elapsed", "12:00"
    assert_select "#{row} .elapsed[data-elapsed-since='#{((NOW - 12.minutes).to_f * 1000).to_i}']"
    assert_select "#{row} .board-login", "1:48 PM"
    events = JSON.parse(css_select(row).first["data-events"])
    assert_equal [ [ ((NOW - 12.minutes).to_f * 1000).to_i, nil, statuses(:on_call).id ] ], events
    assert_select "#{row}[data-status-id='#{statuses(:on_call).id}']"
  end

  test "a status with a time limit hands the limit to the timer so it can turn yellow and red" do
    sign_in_as admin
    get board_path
    assert_select "tr[data-user-id='#{users(:agent_a2).id}'] .elapsed[data-limit-seconds='900']"
    assert_select "tr[data-user-id='#{users(:agent_a1).id}'] .elapsed[data-limit-seconds]", false
  end

  test "time in status measures from the start of the run, not the latest of several same-status events" do
    put(users(:agent_a1), :on_call, NOW - 6.minutes)
    sign_in_as admin
    get board_path
    assert_select "tr[data-user-id='#{users(:agent_a1).id}'] .elapsed", "12:00"
  end

  test "the footer counts agents in each status" do
    sign_in_as admin
    get board_path
    totals = css_select("#board-totals .badge").to_h { |b| b.text.strip.split(" ", 2).then { |n, name| [ name, n.to_i ] } }
    assert_equal({ "Available" => 1, "On Call" => 1, "Break" => 1, "Offline" => 1 }, totals)
  end

  test "a manager sees only their teams' agents and gets team streams, not the organization stream" do
    sign_in_as manager
    get board_path
    assert_equal %w[Alex\ Agent Avery\ Agent Blake\ Agent], names_on_board
    assert_select "tr.board-row[data-team-id='#{teams(:team_c).id}']", false
    assert_select "select[aria-label=Team] option", 3 # All + A + B
    sources = css_select("turbo-cable-stream-source").size
    assert_equal 2, sources, "one per granted team"
    assert_select "turbo-cable-stream-source[signed-stream-name]", 2
  end

  test "an admin listens to one organization-wide stream" do
    sign_in_as admin
    get board_path
    assert_equal 1, css_select("turbo-cable-stream-source").size
  end

  test "managers with a different team set see different boards" do
    sign_in_as users(:manager_c)
    get board_path
    assert_equal %w[Casey\ Agent], names_on_board
  end

  test "agents can't open the board" do
    sign_in_as agent
    get board_path
    assert_redirected_to root_path
  end

  test "signed-out visitors are sent to sign in" do
    get board_path
    assert_redirected_to new_session_path
  end

  test "the board link appears only for people who can use it" do
    sign_in_as manager
    get root_path
    assert_select "nav a", "Board"
    assert_select "a.btn", "Open the live board"
    sign_out
    sign_in_as agent
    get root_path
    assert_select "nav a", text: "Board", count: 0
  end

  test "an agent sees their own live status on their home page" do
    sign_in_as agent
    get root_path
    assert_select "#my-status .badge", "On Call"
    assert_select "#my-status .elapsed", "12:00"
  end

  test "an empty organization gets a helpful message" do
    User.where(role: "agent", organization: organizations(:summit)).update_all(active: false)
    sign_in_as admin
    get board_path
    assert_select "td", /No agents to show/
  end

  test "the filters and sort controls are there" do
    sign_in_as admin
    get board_path
    assert_select "#board-controls input[type=search]"
    assert_select "#board-controls select option", text: "Sort: time in status"
    assert_select "#board-controls select option", text: "Break"
  end

  test "the time shown uses the organization's time zone" do
    organizations(:summit).update!(timezone: "America/Los_Angeles")
    sign_in_as admin
    get board_path
    assert_select "tr[data-user-id='#{users(:agent_a1).id}'] .board-login", "11:48 AM"
    assert_select "[data-board-time-zone-value='America/Los_Angeles']"
  end
end
