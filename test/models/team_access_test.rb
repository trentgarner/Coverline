require "test_helper"

class TeamAccessTest < ActiveSupport::TestCase
  test "grants a manager a team" do
    access = TeamAccess.new(user: users(:manager_c), team: teams(:team_a))
    assert access.valid?, access.errors.full_messages.to_sentence
  end

  test "only managers can be granted teams" do
    assert_not TeamAccess.new(user: agent, team: teams(:team_a)).valid?
    assert_not TeamAccess.new(user: admin, team: teams(:team_a)).valid?
  end

  test "no duplicate grants" do
    assert_not TeamAccess.new(user: users(:manager_ab), team: teams(:team_a)).valid?
  end

  test "a team from another organization can't be granted" do
    assert_not TeamAccess.new(user: users(:manager_c), team: teams(:other_team)).valid?
  end

  test "removing a team or a manager removes the grants" do
    assert_difference "TeamAccess.count", -1 do
      teams(:team_a).destroy
    end
    assert_difference "TeamAccess.count", -1 do # Maya's remaining grant (Team B)
      users(:manager_ab).destroy
    end
  end
end
