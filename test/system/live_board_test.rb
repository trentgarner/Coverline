require "test_helper"
require "application_system_test_case"
require "net/http"

# Phase 4 "done when": two browsers watch the same board; a status change shows on both within ~1 second.
class LiveBoardTest < ApplicationSystemTestCase
  setup do
    @key = organizations(:summit).generate_api_key!
    @a1, @a2, @b1, @c1 = users(:agent_a1), users(:agent_a2), users(:agent_b1), users(:agent_c1)
    put(@a1, :on_call, 12.minutes.ago)
    put(@a2, :break, 20.minutes.ago)
    put(@b1, :available, 2.hours.ago)
    put(@c1, :offline, 5.hours.ago)
  end

  def put(user, status, at) = StatusEvents::Recorder.call(user: user, status: statuses(status), at: at, source: "phone")

  # Sends an event to the real webhook over HTTP, like the phone system.
  def phone_event(agent_id, code)
    uri = URI.join(Capybara.current_session.server.base_url, "/api/v1/status_events")
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{@key}")
    req.body = { agent_id: agent_id, status_code: code, occurred_at: Time.current.utc.iso8601, event_id: SecureRandom.uuid }.to_json
    res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
    assert_equal "200", res.code, res.body
  end

  def row(user) = "tr#board_row_user_#{user.id}"

  def open_board_as(user)
    sign_in_through_browser(user)
    visit board_path
    assert_selector "#live-badge", text: "Live", wait: 5
  end

  test "two browsers watching the board both see a status change within about a second" do
    using_session(:admin_browser) { open_board_as(admin) }
    using_session(:manager_browser) { open_board_as(manager) }

    using_session(:admin_browser) { assert_selector "#{row(@a1)} .board-status", text: "On Call" }
    using_session(:manager_browser) { assert_selector "#{row(@a1)} .board-status", text: "On Call" }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    phone_event("A1001", "AUX-2") # Alex -> Break
    elapsed = {}
    %i[admin_browser manager_browser].each do |name|
      using_session(name) do
        assert_selector "#{row(@a1)} .board-status", text: "Break", wait: 3
        elapsed[name] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      end
    end
    puts "\nlive update latency: #{elapsed.transform_values { |v| v.round(2) }}" if ENV["SHOW_LATENCY"]
    assert_operator elapsed.values.max, :<, 2.5, "both browsers should update in about a second (took #{elapsed.transform_values { |v| v.round(2) }})"

    using_session(:admin_browser) do
      assert_selector "#{row(@a1)}.row-flash", wait: 1, text: "Alex Agent"
      assert_selector "#{row(@a1)} .elapsed-warn, #{row(@a1)} .elapsed", text: /\A0:0\d\z/ # a fresh timer: the new status just began
    end
  end

  test "the footer counts and the timer move without reloading" do
    open_board_as(admin)
    totals = -> { all("#board-totals .badge").to_h { |b| b.text.split(" ", 2).then { |n, name| [ name, n.to_i ] } } }
    assert_equal({ "Available" => 1, "On Call" => 1, "Break" => 1, "Offline" => 1 }.merge("Unmapped" => 0).slice(*totals.call.keys), totals.call.slice("Available", "On Call", "Break", "Offline"))

    phone_event("B1001", "InCall") # Blake: Available -> On Call
    assert_selector "#board-totals .badge", text: "2 On Call", wait: 3
    assert_selector "#board-totals .badge", text: "0 Available"

    timer = find("#{row(@a2)} .elapsed")
    first = timer.text
    assert_match(/\A\d+:\d\d\z/, first)
    sleep 2.2
    assert_not_equal first, find("#{row(@a2)} .elapsed").text, "the timer counts up on its own"
  end

  test "a break past its limit turns the timer yellow, then red" do
    put(@a2, :break, 17.minutes.ago) # limit is 15 minutes, so 17 is past it
    put(@b1, :break, 25.minutes.ago) # 25 is past 1.5 x 15
    put(@c1, :break, 3.minutes.ago)
    open_board_as(admin)
    assert_selector "#{row(@a2)} .elapsed.elapsed-warn"
    assert_selector "#{row(@b1)} .elapsed.elapsed-over"
    assert_no_selector "#{row(@c1)} .elapsed-warn"
    assert_no_selector "#{row(@c1)} .elapsed-over"
  end

  test "search, team and status filters work instantly and stay put as rows change" do
    open_board_as(admin)
    assert_selector "tr.board-row", count: 4
    assert_text "4 of 4 agents"

    fill_in_search "ave" # Avery
    assert_selector "tr.board-row:not([hidden])", count: 1
    assert_selector "#{row(@a2)}:not([hidden])"
    assert_text "1 of 4 agents"
    assert_includes current_url, "q=ave"
    find("button", text: "Reset").click
    assert_selector "tr.board-row:not([hidden])", count: 4

    find("select[aria-label=Status]").select("On Call")
    assert_selector "tr.board-row:not([hidden])", count: 1
    assert_selector "#{row(@a1)}:not([hidden])"

    # Blake goes on a call: he now matches the filter and appears, with no reload.
    phone_event("B1001", "InCall")
    assert_selector "tr.board-row:not([hidden])", count: 2, wait: 3
    assert_selector "#{row(@b1)}:not([hidden])"
    # ...and Alex leaving On Call makes him drop out of the filtered view.
    phone_event("A1001", "Ready")
    assert_selector "tr.board-row:not([hidden])", count: 1, wait: 3
    assert_no_selector "#{row(@a1)}:not([hidden])"
    assert_includes current_url, "status="

    find("select[aria-label=Status]").select("Any status")
    find("select[aria-label=Team]").select("Sales Team B")
    assert_selector "tr.board-row:not([hidden])", count: 1
    assert_selector "tr[data-team-header]:not([hidden])", count: 1, text: "Sales Team B"
  end

  test "filters survive a page reload through the address bar" do
    open_board_as(admin)
    find("select[aria-label=Team]").select("Sales Team A")
    assert_selector "tr.board-row:not([hidden])", count: 2
    visit current_url
    assert_selector "tr.board-row:not([hidden])", count: 2
    assert_equal teams(:team_a).id.to_s, find("select[aria-label=Team]").value
  end

  test "sorting by time in status and by status reorders rows within each team" do
    open_board_as(admin)
    order = -> { all("tr[data-team-id='#{teams(:team_a).id}'].board-row").map { |r| r["data-user-id"].to_i } }
    assert_equal [ @a1.id, @a2.id ], order.call # by name: Alex, Avery

    find("select[aria-label='Sort by']").select("Sort: time in status")
    assert_equal [ @a2.id, @a1.id ], order.call # Avery has been in Break longest (20 min vs 12)

    find("select[aria-label='Sort by']").select("Sort: status")
    assert_equal [ @a1.id, @a2.id ], order.call # On Call comes before Break in the status order

    phone_event("A1002", "Ready") # Avery -> Available, which sorts first
    assert_equal [ @a2.id, @a1.id ], begin
      sleep 0.2
      assert_selector "#{row(@a2)}", text: "Available", wait: 3
      order.call
    end
  end

  test "each row draws a horizontal bar of the day, with a now line" do
    put(@a1, :available, 40.minutes.ago)
    open_board_as(admin)
    within row(@a1) do
      assert_selector ".board-bar .board-seg", minimum: 2
      assert_selector ".board-bar .board-now"
    end
    assert_selector ".board-axis .board-tick", minimum: 8
    before = all("#{row(@a1)} .board-seg").size
    phone_event("A1001", "AUX-2")
    assert_selector "#{row(@a1)} .board-seg", count: before + 1, wait: 3
  end

  test "managers don't receive other teams' changes" do
    open_board_as(manager)
    assert_no_selector row(@c1)
    phone_event("C1001", "Ready") # Casey on Team C: not on Maya's board
    sleep 0.8
    assert_no_selector row(@c1)
    assert_selector "tr.board-row", count: 3
    phone_event("B1001", "AUX-2") # Blake on Team B: is
    assert_selector "#{row(@b1)} .board-status", text: "Break", wait: 3
  end

  test "adding an agent refreshes the board for everyone watching" do
    using_session(:watcher) { open_board_as(admin) }
    using_session(:watcher) { assert_selector "tr.board-row", count: 4 }
    User.create!(organization: organizations(:summit), team: teams(:team_b), role: "agent", first_name: "Zed", last_name: "Zimmer",
                 email_address: "zed@example.com", password: "password", phone_agent_id: "B1009")
    Board::Broadcaster.roster_changed(organizations(:summit), teams(:team_b))
    using_session(:watcher) { assert_selector "tr.board-row", count: 5, wait: 4 }
  end

  test "an agent's own page updates by itself too" do
    sign_in_through_browser(agent)
    visit agent_path(agent)
    assert_selector "#current-status .badge", text: "On Call"
    assert_selector "#day-bar-card .board-seg", minimum: 1
    assert_selector "#current-status .elapsed"
    sleep 1 # let the stream connect
    phone_event("A1001", "AUX-2")
    assert_selector "#current-status .badge", text: "Break", wait: 4
    assert_selector "#todays-events tbody tr", count: 2
  end

  private

  def fill_in_search(text)
    find("input[type=search]").set(text)
  end
end
