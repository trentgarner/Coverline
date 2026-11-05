require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build(attrs = {})
    User.new({ organization: organizations(:summit), team: teams(:team_a), first_name: "New", last_name: "Person",
               email_address: "new.person@example.com", password: "password" }.merge(attrs))
  end

  test "valid with the basics, and defaults to agent" do
    u = build
    assert u.valid?, u.errors.full_messages.to_sentence
    assert u.agent?
  end

  test "needs a name, and a unique well-formed email" do
    assert_not build(first_name: "").valid?
    assert_not build(last_name: "").valid?
    assert_not build(email_address: "not-an-email").valid?
    assert_not build(email_address: "ALEX@example.com").valid?, "emails are case-insensitive"
  end

  test "email is normalized" do
    assert_equal "mixed.case@example.com", build(email_address: "  Mixed.Case@Example.com ").tap(&:valid?).email_address
  end

  test "role must be one of the four" do
    assert_raises(ArgumentError) { build(role: "owner") }
    User::ROLES.each { |r| assert build(role: r).valid?, r }
  end

  test "phone agent id is unique within an organization but blank is fine" do
    assert_not build(phone_agent_id: "A1001").valid?
    assert build(phone_agent_id: "").valid?
    assert build(phone_agent_id: nil).valid?
    assert build(phone_agent_id: "A1001", organization: organizations(:other), team: nil).valid?
  end

  test "a team must belong to the same organization" do
    assert_not build(team: teams(:other_team)).valid?
  end

  test "role helpers: each role includes the ones below it" do
    assert agent.agent?
    assert_not agent.at_least?(:manager)
    assert manager.at_least?(:agent) && manager.at_least?(:manager) && !manager.at_least?(:admin)
    assert admin.admin_or_above?
    assert super_user.at_least?(:super_user)
  end

  test "visible teams follow the role" do
    assert_empty agent.visible_teams
    assert_equal %w[team_a team_b].map { |t| teams(t.to_sym).id }.sort, manager.visible_teams.pluck(:id).sort
    assert_equal 3, admin.visible_teams.count
  end

  test "active scope and full name" do
    assert_not User.active.exists?(users(:inactive_agent).id)
    assert_equal "Alex Agent", agent.full_name
  end

  test "password is required and checked" do
    assert_nil User.authenticate_by(email_address: "alex@example.com", password: "wrong")
    assert_equal agent, User.authenticate_by(email_address: "alex@example.com", password: "password")
  end
end
