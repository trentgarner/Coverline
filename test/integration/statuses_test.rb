require "test_helper"

class StatusesTest < ActionDispatch::IntegrationTest
  def status_params(overrides = {})
    { status: { name: "Training", color: "#26a69a", category: "other", time_limit_minutes: "",
                productive: "0", counts_toward_cft: "0", active: "1", phone_codes_text: "AUX-5\nTraining" }.merge(overrides) }
  end

  test "an admin adds a colored status with phone codes, appended to the end of the order" do
    sign_in_as admin
    assert_difference "Status.count", 1 do
      assert_difference "StatusCode.count", 2 do # AUX-5 and Training
        post statuses_path, params: status_params
      end
    end
    s = Status.find_by!(name: "Training")
    assert_redirected_to statuses_path
    assert_equal [ "#26a69a", "other", 5 ], [ s.color, s.category, s.sort_order ]
    assert_equal %w[AUX-5 Training], s.status_codes.pluck(:phone_code).sort
    assert_equal admin, AuditLog.where(action: "created", target_type: "Status").last.user
  end

  test "the list shows each status as a pill in its own color" do
    sign_in_as admin
    get statuses_path
    assert_select "tr[data-status='Break'] .badge[style*='#e8883a']"
    assert_select "tr[data-status='Break']", /15 min/
    assert_select "tr[data-status='Break']", /AUX-2, Break/
    assert_select "tr[data-status='Offline'] .badge[style*='#6c757d']"
  end

  test "pill text is dark on light colors and white on dark ones" do
    helper = ApplicationController.helpers
    assert_equal "#ffffff", helper.readable_text_color("#1f6fb2")
    assert_equal "#212529", helper.readable_text_color("#ffe082")
    assert_equal "#212529", helper.readable_text_color("#ffffff")
    assert_equal "#ffffff", helper.readable_text_color("#000000")
  end

  test "editing updates fields and replaces phone codes, logging the change" do
    sign_in_as admin
    patch status_path(statuses(:break)), params: { status: { color: "#ff0000", time_limit_minutes: "20", phone_codes_text: "AUX-2\nCoffee" } }
    b = statuses(:break).reload
    assert_equal [ "#ff0000", 20 ], [ b.color, b.time_limit_minutes ]
    assert_equal %w[AUX-2 Coffee], b.status_codes.pluck(:phone_code).sort
    log = AuditLog.where(action: "updated", target_type: "Status").last
    assert_equal [ "#e8883a", "#ff0000" ], log.changes_hash["color"]
    assert_equal [ [ "AUX-2", "Break" ], [ "AUX-2", "Coffee" ] ], log.changes_hash["phone_codes"]
  end

  test "a status can be deactivated" do
    sign_in_as admin
    patch status_path(statuses(:break)), params: { status: { active: "0" } }
    assert_not statuses(:break).reload.active?
  end

  test "invalid color, duplicate name, and clashing phone codes are refused with messages" do
    sign_in_as admin
    assert_no_difference "Status.count" do
      post statuses_path, params: status_params(color: "green")
      assert_select ".alert-danger", /hex color/
      post statuses_path, params: status_params(name: "available")
      assert_select ".alert-danger", /Name/
      post statuses_path, params: status_params(phone_codes_text: "ready")
      assert_select ".alert-danger", /already used/
    end
    assert_response :unprocessable_entity
  end

  test "the same code can't be claimed by editing a different status either" do
    sign_in_as admin
    patch status_path(statuses(:offline)), params: { status: { phone_codes_text: "AUX-2" } }
    assert_response :unprocessable_entity
    assert_equal %w[LOGGEDOUT], statuses(:offline).reload.status_codes.pluck(:phone_code)
  end

  test "drag-to-reorder saves the new order and logs it" do
    sign_in_as admin
    order = [ statuses(:offline), statuses(:break), statuses(:on_call), statuses(:available) ].map(&:id)
    patch reorder_statuses_path, params: { ids: order }
    assert_response :no_content
    assert_equal %w[Offline Break On\ Call Available], Status.where(organization: organizations(:summit)).ordered.pluck(:name)
    assert_equal "reordered", AuditLog.last.action
  end

  test "reordering can't touch another organization's statuses" do
    sign_in_as admin
    patch reorder_statuses_path, params: { ids: [ statuses(:other_org_status).id, statuses(:available).id ] }
    assert_equal 1, statuses(:other_org_status).reload.sort_order
    assert_equal 2, statuses(:available).reload.sort_order
  end

  test "an admin can't see or change another organization's statuses" do
    sign_in_as admin
    get statuses_path
    assert_select "tr[data-status]", 4
    get edit_status_path(statuses(:other_org_status))
    assert_response :not_found
    patch status_path(statuses(:other_org_status)), params: { status: { name: "Hacked" } }
    assert_response :not_found
  end

  test "managers and agents cannot open or change statuses" do
    [ manager, agent ].each do |u|
      sign_in_as u
      [ statuses_path, new_status_path, edit_status_path(statuses(:break)) ].each do |path|
        get path
        assert_redirected_to root_path, "#{u.role} #{path}"
      end
      assert_no_difference "Status.count" do
        post statuses_path, params: status_params
      end
      patch status_path(statuses(:break)), params: { status: { name: "Nope" } }
      patch reorder_statuses_path, params: { ids: [ statuses(:break).id ] }
      assert_equal "Break", statuses(:break).reload.name
      assert_equal 3, statuses(:break).sort_order
      delete session_path
    end
  end
end
