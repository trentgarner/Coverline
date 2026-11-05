ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
    set_fixture_class team_access: TeamAccess

    # The four roles plus a few supporting people, by fixture name.
    def agent = users(:agent_a1)
    def manager = users(:manager_ab)
    def admin = users(:admin)
    def super_user = users(:super)

    # One agent's timeline, oldest first, as [status name, from, to] (to is nil while current).
    def timeline_of(user) = user.status_events.reload.in_order.map { |e| [ e.status.name, e.started_at, e.ended_at ] }

    # The rules every timeline must obey, however events arrived: exactly one open event (the last),
    # and each event ends precisely when the next one starts.
    def assert_timeline_consistent(user)
      events = user.status_events.reload.in_order.to_a
      return if events.empty?
      assert_equal 1, events.count { |e| e.ended_at.nil? }, "exactly one open event for #{user.full_name}"
      assert_nil events.last.ended_at, "only the latest event is open"
      events.each_cons(2) { |a, b| assert_equal b.started_at, a.ended_at, "#{a.status.name} should end when #{b.status.name} starts" }
    end
  end
end
