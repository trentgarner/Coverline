require "test_helper"

# Phase 2 "done when": an admin builds a team of 25 agents and 8 colored statuses.
# (The 15-minute budget is about a person at the keyboard; here we prove the app lets them
# do it in a handful of steps: one team, one pasted list, eight short forms.)
class Phase2WorkflowTest < ActionDispatch::IntegrationTest
  test "an admin builds a team of 25 agents and 8 colored statuses" do
    sign_in_as admin

    post teams_path, params: { team: { name: "Sales Team D" } }
    team = Team.find_by!(name: "Sales Team D")

    list = (1..25).map { |i| "Agent#{i}, Dee#{i}, agent#{i}.dee@example.com, D#{1000 + i}" }.join("\n")
    post bulk_create_agents_path, params: { team_id: team.id, list: list }
    assert_response :success
    assert_equal 25, team.users.where(role: "agent").count
    assert_select "#new-credentials tbody tr", 25

    statuses = [
      [ "Idle", "ready", "#2f9e6f" ], [ "Talking", "on_call", "#1f6fb2" ], [ "After Call", "wrap_up", "#7e57c2" ],
      [ "Short Break", "break", "#e8883a" ], [ "Meal", "lunch", "#d9534f" ], [ "Huddle", "meeting", "#8d6e63" ],
      [ "Learning", "other", "#26a69a" ], [ "Signed Out", "offline", "#6c757d" ]
    ]
    statuses.each_with_index do |(name, category, color), i|
      defaults = Status.flag_defaults_for(category)
      post statuses_path, params: { status: { name: name, category: category, color: color, productive: defaults[:productive] ? "1" : "0",
                                              counts_toward_cft: defaults[:counts_toward_cft] ? "1" : "0", active: "1", phone_codes_text: "CODE-#{i}" } }
      assert_redirected_to statuses_path
    end

    new_names = statuses.map(&:first)
    created = Status.where(organization: organizations(:summit), name: new_names)
    assert_equal 8, created.count
    assert_equal 8, created.map(&:color).uniq.size, "each status has its own color"
    assert_equal %w[Idle Talking], created.select(&:counts_toward_cft?).map(&:name).sort
    get statuses_path
    assert_select "#statuses tbody tr[data-status]", 12 # 4 fixtures + 8 new

    get team_path(team)
    assert_select "#members [data-member]", 25
  end
end
