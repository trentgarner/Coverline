require "test_helper"

class TeamTest < ActiveSupport::TestCase
  test "needs a name that is unique within the organization" do
    assert_not Team.new(organization: organizations(:summit), name: "").valid?
    assert_not Team.new(organization: organizations(:summit), name: "Sales Team A").valid?
    assert Team.new(organization: organizations(:other), name: "Sales Team A").valid?
  end

  test "deleting a team keeps its agents, just unassigned" do
    teams(:team_c).destroy
    assert_nil users(:agent_c1).reload.team_id
  end
end
