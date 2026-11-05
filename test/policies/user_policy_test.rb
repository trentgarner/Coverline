require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  def policy(actor, target) = UserPolicy.new(actor, target)

  test "an admin manages agents and managers but not admins or super users" do
    assert policy(admin, users(:agent_a1)).update?
    assert policy(admin, users(:manager_c)).update?
    assert_not policy(admin, users(:second_admin)).update?
    assert_not policy(admin, users(:super)).update?
    assert_not policy(admin, users(:second_admin)).destroy?
  end

  test "a super user manages everyone in the org" do
    [ :agent_a1, :manager_c, :second_admin, :admin ].each { |f| assert policy(super_user, users(f)).update?, f }
  end

  test "nobody can deactivate themselves" do
    assert_not policy(admin, admin).destroy?
    assert_not policy(super_user, super_user).destroy?
    assert policy(admin, users(:agent_a1)).destroy?
  end

  test "assignable roles: admins can't create admins, only a super user can" do
    assert_empty policy(agent, agent).assignable_roles
    assert_empty policy(manager, agent).assignable_roles
    assert_equal %w[agent manager], policy(admin, agent).assignable_roles
    assert_equal User::ROLES, policy(super_user, agent).assignable_roles
  end

  test "admins and super users cannot reach into another organization" do
    assert_not policy(admin, users(:other_agent)).update?
    assert_not policy(super_user, users(:other_agent)).update?
    assert_not policy(admin, users(:other_agent)).show?
    assert_not BoardPolicy.new(admin, users(:other_agent)).override_status?
  end

  test "people can always see themselves; managers only their teams' people" do
    assert policy(agent, agent).show?
    assert_not policy(agent, users(:agent_a2)).show?
    assert policy(manager, users(:agent_b1)).show?
    assert_not policy(manager, users(:agent_c1)).show?
    assert policy(admin, users(:agent_c1)).show?
  end

  test "a manager can override only the statuses of agents on their own teams" do
    assert BoardPolicy.new(users(:manager_ab), users(:agent_b1)).override_status?
    assert_not BoardPolicy.new(users(:manager_ab), users(:agent_c1)).override_status?
    assert BoardPolicy.new(users(:manager_c), users(:agent_c1)).override_status?
    assert_not BoardPolicy.new(users(:manager_c), users(:agent_a1)).override_status?
    assert BoardPolicy.new(admin, users(:agent_c1)).override_status?
    assert_not BoardPolicy.new(agent, users(:agent_a2)).override_status?
    assert_not BoardPolicy.new(agent, agent).override_status?
  end

  test "a team in another organization can't be managed" do
    assert_not TeamPolicy.new(admin, teams(:other_team)).update?
    assert_not TeamPolicy.new(admin, teams(:other_team)).grant_access?
    assert_not TeamPolicy.new(manager, teams(:team_c)).show?
    assert TeamPolicy.new(manager, teams(:team_a)).show?
  end
end
