require "test_helper"

class StatusEventsApiTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 1, 20, 0, 0)
    @key = organizations(:summit).generate_api_key!
  end

  def post_events(body, key: @key)
    headers = { "Content-Type" => "application/json" }
    headers["Authorization"] = "Bearer #{key}" if key
    post api_v1_status_events_path, params: body.to_json, headers: headers
  end

  def event(overrides = {})
    { agent_id: "A1001", status_code: "Ready", occurred_at: "2026-11-01T15:00:00Z", event_id: "evt-1" }.merge(overrides)
  end

  test "a single event is recorded" do
    post_events(event)
    assert_response :success
    assert_equal [ { "event_id" => "evt-1", "outcome" => "recorded" } ], response.parsed_body["results"]
    assert_equal statuses(:available), users(:agent_a1).reload.current_status
  end

  test "a batch is processed event by event, reporting each outcome" do
    post_events({ events: [ event, event(event_id: "evt-2", status_code: "InCall", occurred_at: "2026-11-01T15:05:00Z"),
                          event(event_id: "evt-3", agent_id: "ZZ999"), event(event_id: "evt-4", status_code: "AUX-77", agent_id: "A1002") ] })
    assert_response :success
    assert_equal %w[recorded recorded unknown_agent unmapped_code], response.parsed_body["results"].map { |r| r["outcome"] }
    assert_equal %w[Available On\ Call], users(:agent_a1).status_events.in_order.map { |e| e.status.name }
    assert_equal "Unmapped", users(:agent_a2).reload.current_status.name
  end

  test "sending the same event again is harmless" do
    post_events(event)
    assert_no_difference "StatusEvent.count" do
      post_events(event)
    end
    assert_equal "duplicate", response.parsed_body["results"].first["outcome"]
    post_events({ events: [ event, event ] })
    assert_equal %w[duplicate duplicate], response.parsed_body["results"].map { |r| r["outcome"] }
    assert_equal 1, users(:agent_a1).status_events.count
  end

  test "bad events are reported without stopping the rest of the batch" do
    post_events({ events: [ event(occurred_at: "nonsense"), event(event_id: "good") ] })
    assert_response :success
    first, second = response.parsed_body["results"]
    assert_equal "invalid", first["outcome"]
    assert_match "ISO 8601", first["detail"]
    assert_equal "recorded", second["outcome"]
  end

  test "no key, a wrong key and a replaced key are all turned away" do
    post_events(event, key: nil)
    assert_response :unauthorized
    post_events(event, key: "cvl_not_a_real_key")
    assert_response :unauthorized
    old = @key
    organizations(:summit).generate_api_key!
    post_events(event, key: old)
    assert_response :unauthorized
    assert_equal 0, StatusEvent.count
  end

  test "an organization with no key at all can't be reached" do
    post api_v1_status_events_path, params: event.to_json, headers: { "Content-Type" => "application/json", "Authorization" => "Bearer " }
    assert_response :unauthorized
  end

  test "a key only ever touches its own organization's agents" do
    users(:other_agent).update!(phone_agent_id: "A1001")
    post_events(event) # summit's key
    assert_equal 1, users(:agent_a1).status_events.count
    assert_equal 0, users(:other_agent).status_events.count
    other_key = organizations(:other).generate_api_key!
    post_events(event(event_id: "evt-2"), key: other_key)
    assert_equal 1, users(:other_agent).status_events.count
    assert_equal 1, users(:agent_a1).status_events.count
  end

  test "an oversized batch is refused" do
    post_events({ events: Array.new(501) { |i| event(event_id: "e#{i}") } })
    assert_response :content_too_large
    assert_equal 0, StatusEvent.count
  end

  test "the endpoint works without a browser session or CSRF token" do
    post api_v1_status_events_path, params: event.to_json, headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@key}" }
    assert_response :success
  end

  test "a deactivated agent's events are ignored but reported" do
    users(:agent_a1).update!(active: false)
    post_events(event)
    assert_equal "inactive_agent", response.parsed_body["results"].first["outcome"]
    assert_equal 0, StatusEvent.count
  end
end
