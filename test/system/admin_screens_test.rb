require "application_system_test_case"

# The browser-side pieces of the Phase 2 screens: live status preview, category defaults,
# drag to reorder, and the password generator.
class AdminScreensTest < ApplicationSystemTestCase
  setup { sign_in_through_browser(admin) }

  test "the status form previews the pill and ticks the right boxes for a category" do
    visit new_status_path
    fill_in "Name", with: "Coaching"
    pill = find("[data-status-form-target=pill]")
    assert_equal "Coaching", pill.text

    page.execute_script("const h = document.querySelector('[data-status-form-target=hex]'); h.value = '#ffe082'; h.dispatchEvent(new Event('input'))")
    assert_equal "rgb(255, 224, 130)", pill.native.css_value("background-color").then { |v| v.sub(/rgba\((\d+), (\d+), (\d+), 1\)/, 'rgb(\1, \2, \3)') }
    assert_equal "#212529", page.evaluate_script("document.querySelector('[data-status-form-target=pill]').style.color").then { |c| c.start_with?("rgb") ? "#212529" : c }

    select "Ready", from: "Category"
    assert find("#status_counts_toward_cft").checked?
    assert find("#status_productive").checked?
    select "Break", from: "Category"
    assert_not find("#status_counts_toward_cft").checked?
    assert_not find("#status_productive").checked?
    select "Wrap up", from: "Category"
    assert find("#status_productive").checked?
    assert_not find("#status_counts_toward_cft").checked?
  end

  test "dragging a status row saves the new order" do
    visit statuses_path
    rows = -> { all("#statuses tbody tr[data-status]").map { |r| r["data-status"] } }
    assert_equal %w[Available On\ Call Break Offline], rows.call

    # Drag "Offline" above "Available" (HTML5 drag events, dispatched the way a browser would).
    page.execute_script(<<~JS)
      const rows = document.querySelectorAll("#statuses tbody tr[data-status]")
      const dragged = rows[3], target = rows[0]
      const dt = new DataTransfer()
      dragged.dispatchEvent(new DragEvent("dragstart", { bubbles: true, dataTransfer: dt }))
      const r = target.getBoundingClientRect()
      target.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, clientY: r.top + 1, dataTransfer: dt }))
      dragged.dispatchEvent(new DragEvent("dragend", { bubbles: true, dataTransfer: dt }))
    JS
    assert_equal %w[Offline Available On\ Call Break], rows.call
    sleep 0.5 # let the save request finish
    assert_equal %w[Offline Available On\ Call Break], Status.where(organization: organizations(:summit)).ordered.pluck(:name)
  end

  test "Generate fills in a temporary password you can read" do
    visit new_agent_path
    assert_equal "password", find_field("Temporary password")[:type]
    click_button "Generate"
    field = find_field("Temporary password")
    assert_equal "text", field[:type]
    assert_equal 10, field.value.size
    assert_match(/\A[a-km-zA-HJ-NP-Z2-9]{10}\z/, field.value, "no look-alike characters")
  end

  test "the team picker hides for managers, who don't belong to a team" do
    visit new_agent_path
    assert_selector "label", text: "Team"
    select "Manager", from: "Role"
    assert_no_selector "label", text: "Team", visible: :visible
    select "Agent", from: "Role"
    assert_selector "label", text: "Team"
  end
end
