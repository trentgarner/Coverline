require "test_helper"

class IntegrationScreenTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.utc(2026, 11, 1, 20, 0, 0) }

  def send_events(key, *events)
    post api_v1_status_events_path, params: { events: events }.to_json, headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{key}" }
  end

  test "only a Super User can open it" do
    [ admin, manager, agent ].each do |u|
      sign_in_as u
      get integration_path
      assert_redirected_to root_path, u.role
      post regenerate_key_integration_path
      assert_redirected_to root_path
      delete session_path
    end
    assert_not organizations(:summit).reload.api_key?
    sign_in_as super_user
    get integration_path
    assert_response :success
    assert_select "#webhook-url", /api\/v1\/status_events/
    assert_select "#api-key-status", /No key yet/
  end

  test "generating a key shows it once, and it then works on the webhook" do
    sign_in_as super_user
    post regenerate_key_integration_path
    assert_response :success
    key = css_select("#new-api-key .font-monospace").first.text.strip
    assert_match(/\Acvl_/, key)
    assert AuditLog.exists?(action: "api_key_regenerated")

    get integration_path
    assert_select "#new-api-key", false
    assert_select "#api-key-status", /#{Regexp.escape(key.first(8))}/
    assert_not_includes response.body, key

    delete session_path
    send_events(key, { agent_id: "A1001", status_code: "Ready", occurred_at: "2026-11-01T15:00:00Z", event_id: "k1" })
    assert_response :success
    assert_equal "recorded", response.parsed_body["results"].first["outcome"]
  end

  test "regenerating kills the old key" do
    sign_in_as super_user
    post regenerate_key_integration_path
    old = css_select("#new-api-key .font-monospace").first.text.strip
    post regenerate_key_integration_path
    new = css_select("#new-api-key .font-monospace").first.text.strip
    assert_not_equal old, new
    delete session_path
    send_events(old, { agent_id: "A1001", status_code: "Ready", occurred_at: "2026-11-01T15:00:00Z", event_id: "k2" })
    assert_response :unauthorized
  end

  test "unmapped codes are listed, and mapping one teaches the system" do
    key = organizations(:summit).generate_api_key!
    send_events(key, { agent_id: "A1001", status_code: "AUX-9", occurred_at: "2026-11-01T15:00:00Z", event_id: "m1" },
                     { agent_id: "A1002", status_code: "AUX-9", occurred_at: "2026-11-01T15:01:00Z", event_id: "m2" })
    sign_in_as super_user
    get integration_path
    assert_select "#unmapped-codes form[data-code='AUX-9']"
    assert_select "#unmapped-codes", /×2/

    post map_code_integration_path, params: { phone_code: "AUX-9", status_id: statuses(:break).id }
    assert_redirected_to integration_path
    assert_includes statuses(:break).reload.status_codes.pluck(:phone_code), "AUX-9"
    assert_equal 0, organizations(:summit).unmatched_events.unmapped_codes.unresolved.count
    assert AuditLog.exists?(action: "mapped_code")

    delete session_path
    send_events(key, { agent_id: "A1001", status_code: "AUX-9", occurred_at: "2026-11-01T15:30:00Z", event_id: "m3" })
    assert_equal "recorded", response.parsed_body["results"].first["outcome"]
    assert_equal "Break", users(:agent_a1).reload.current_status.name
  end

  test "mapping a code that another status already owns is refused" do
    sign_in_as super_user
    post map_code_integration_path, params: { phone_code: "Ready", status_id: statuses(:break).id }
    assert_redirected_to integration_path
    follow_redirect!
    assert_select ".alert-danger", /already used/
  end

  test "unknown agent IDs are held; linking one replays its events in time order" do
    key = organizations(:summit).generate_api_key!
    send_events(key, { agent_id: "NEW77", status_code: "InCall", occurred_at: "2026-11-01T15:10:00Z", event_id: "h2" },
                     { agent_id: "NEW77", status_code: "Ready", occurred_at: "2026-11-01T15:00:00Z", event_id: "h1" })
    assert_equal 0, StatusEvent.count
    sign_in_as super_user
    get integration_path
    assert_select "#unknown-agents form[data-phone-id='NEW77']"

    post link_agent_integration_path, params: { phone_agent_id: "NEW77", user_id: users(:agent_b1).id }
    assert_redirected_to integration_path
    assert_equal "NEW77", users(:agent_b1).reload.phone_agent_id
    assert_equal %w[Available On\ Call], users(:agent_b1).status_events.in_order.map { |e| e.status.name }
    assert_timeline_consistent(users(:agent_b1))
    assert_equal 0, organizations(:summit).unmatched_events.unknown_agents.unresolved.count
    log = AuditLog.where(action: "linked_phone_id").last
    assert_equal 2, log.changes_hash["events_replayed"]
  end

  test "linking can't use someone else's phone ID, or a person from another organization" do
    sign_in_as super_user
    post link_agent_integration_path, params: { phone_agent_id: "A1002", user_id: users(:agent_b1).id } # taken by Avery
    assert_redirected_to integration_path
    assert_equal "B1001", users(:agent_b1).reload.phone_agent_id
    post link_agent_integration_path, params: { phone_agent_id: "NEW1", user_id: users(:other_agent).id }
    assert_response :not_found
  end

  test "the Statuses page warns admins about unmapped codes, pointing Super Users to the fix" do
    key = organizations(:summit).generate_api_key!
    send_events(key, { agent_id: "A1001", status_code: "AUX-9", occurred_at: "2026-11-01T15:00:00Z", event_id: "w1" })
    sign_in_as admin
    get statuses_path
    assert_select "#unmapped-warning", /AUX-9/
    assert_select "#unmapped-warning a", false
    delete session_path
    sign_in_as super_user
    get statuses_path
    assert_select "#unmapped-warning a[href='#{integration_path}']"
    post map_code_integration_path, params: { phone_code: "AUX-9", status_id: statuses(:break).id }
    get statuses_path
    assert_select "#unmapped-warning", false
  end

  test "Integration shows up in the menu for a Super User only" do
    sign_in_as super_user
    get root_path
    assert_select "nav a", "Integration"
    delete session_path
    sign_in_as admin
    get root_path
    assert_select "nav a", text: "Integration", count: 0
  end
end
