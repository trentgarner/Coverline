require "test_helper"

class AgentStatusTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 1, 18, 0, 0) # noon in Chicago
    StatusEvents::Recorder.call(user: users(:agent_a1), status: statuses(:available), at: Time.utc(2026, 11, 1, 15, 0), source: "phone", external_event_id: "a")
    StatusEvents::Recorder.call(user: users(:agent_a1), status: statuses(:on_call), at: Time.utc(2026, 11, 1, 16, 30), source: "phone", external_event_id: "b")
  end

  test "the agent page shows the current status and today's changes in the organization's time zone" do
    sign_in_as admin
    get agent_path(agent)
    assert_response :success
    assert_select "#current-status .badge", "On Call"
    assert_select "#current-status", /10:30:00 AM/
    assert_select "#todays-events tbody tr", 2
    assert_select "#todays-events tbody tr:first-child", /9:00:00 AM/
    assert_select "#todays-events tbody tr:last-child", /now/
  end

  test "an agent sees their own page, with no override controls" do
    sign_in_as agent
    get agent_path(agent)
    assert_response :success
    assert_select "#current-status .badge", "On Call"
    assert_select "#override", false
    get agent_path(users(:agent_a2))
    assert_response :not_found
  end

  test "a manager sees their team's agents and can set a status by hand" do
    sign_in_as manager
    get agent_path(agent)
    assert_select "#override select option", text: "Break"
    assert_select "#override select option", text: "Unmapped", count: 0
    assert_difference "StatusEvent.count", 1 do
      post override_status_agent_path(agent), params: { status_id: statuses(:break).id }
    end
    assert_redirected_to agent_path(agent)
    assert_equal "Break", agent.reload.current_status.name
    last = agent.status_events.in_order.last
    assert_equal [ "manual", nil ], [ last.source, last.external_event_id ]
    assert_timeline_consistent(agent)
    log = AuditLog.where(action: "status_override").last
    assert_equal [ manager, agent.full_name, [ "On Call", "Break" ] ], [ log.user, log.target_label, log.changes_hash["status"] ]
  end

  test "a manager can't override an agent on someone else's team" do
    sign_in_as manager
    c1 = users(:agent_c1)
    assert_no_difference "StatusEvent.count" do
      post override_status_agent_path(c1), params: { status_id: statuses(:break).id }
    end
    assert_response :not_found
    get agent_path(c1)
    assert_response :not_found
  end

  test "an admin can override anyone in the organization, but not another organization's agents" do
    sign_in_as admin
    post override_status_agent_path(users(:agent_c1)), params: { status_id: statuses(:break).id }
    assert_equal "Break", users(:agent_c1).reload.current_status.name
    post override_status_agent_path(users(:other_agent)), params: { status_id: statuses(:break).id }
    assert_response :not_found
    assert_nil users(:other_agent).reload.current_status
  end

  test "agents can't override anyone, themselves included" do
    sign_in_as agent
    assert_no_difference "StatusEvent.count" do
      post override_status_agent_path(agent), params: { status_id: statuses(:break).id }
    end
    assert_redirected_to root_path
  end

  test "an override can only use this organization's active statuses" do
    sign_in_as admin
    assert_no_difference "StatusEvent.count" do
      post override_status_agent_path(agent), params: { status_id: statuses(:other_org_status).id }
      assert_response :not_found
      statuses(:break).update!(active: false)
      post override_status_agent_path(agent), params: { status_id: statuses(:break).id }
      assert_response :not_found
    end
  end

  test "agents with no history show a friendly empty state" do
    sign_in_as admin
    get agent_path(users(:agent_b1))
    assert_select "#current-status", /No status recorded yet/
    assert_select "#todays-events", /Nothing recorded today/
  end
end
