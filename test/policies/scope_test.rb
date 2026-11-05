require "test_helper"

# "See live board for assigned teams only": who sees which teams and people.
class ScopeTest < ActiveSupport::TestCase
  def teams_for(user) = TeamPolicy::Scope.new(user, Team).resolve.pluck(:name).sort
  def people_for(user) = UserPolicy::Scope.new(user, User).resolve.pluck(:email_address).sort

  test "agents see no teams and only themselves" do
    assert_empty teams_for(agent)
    assert_equal [ "alex@example.com" ], people_for(agent)
  end

  test "a manager sees only the teams they were granted, and those teams' people" do
    assert_equal [ "Sales Team A", "Sales Team B" ], teams_for(users(:manager_ab))
    assert_equal %w[alex@example.com avery@example.com blake@example.com idle@example.com maya@example.com], people_for(users(:manager_ab))
    assert_equal [ "Sales Team C" ], teams_for(users(:manager_c))
    assert_equal %w[casey@example.com marco@example.com], people_for(users(:manager_c))
  end

  test "a manager given an extra team sees it (covering for another manager)" do
    TeamAccess.create!(user: users(:manager_c), team: teams(:team_a))
    assert_equal [ "Sales Team A", "Sales Team C" ], teams_for(users(:manager_c))
    assert_includes people_for(users(:manager_c)), "alex@example.com"
  end

  test "a manager with no teams sees nobody but themselves" do
    TeamAccess.where(user: users(:manager_c)).destroy_all
    assert_empty teams_for(users(:manager_c))
    assert_equal [ "marco@example.com" ], people_for(users(:manager_c))
  end

  test "admins and super users see everything in their organization and nothing outside it" do
    [ users(:admin), users(:super) ].each do |u|
      assert_equal [ "Sales Team A", "Sales Team B", "Sales Team C" ], teams_for(u)
      assert_equal 10, people_for(u).size
      assert_not_includes people_for(u), "olive@other.example.com"
      assert_not_includes people_for(u), "otto@other.example.com"
    end
  end

  test "the other organization is just as isolated" do
    assert_equal [ "Other Team" ], teams_for(users(:other_admin))
    assert_equal %w[olive@other.example.com otto@other.example.com], people_for(users(:other_admin))
  end
end
