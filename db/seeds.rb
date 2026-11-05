# Fake data only: invented company, teams and people. Safe to run repeatedly.
# Everyone signs in with the password below (development only).
PASSWORD = "password".freeze

org = Organization.find_or_create_by!(name: "Summit Sales Co (fake)") { |o| o.timezone = "America/Chicago" }

teams = [ "Sales Team A", "Sales Team B", "Sales Team C" ].index_with do |name|
  Team.find_or_create_by!(organization: org, name: name)
end

def seed_user(org, attrs)
  User.find_or_create_by!(email_address: attrs.fetch(:email_address)) do |u|
    u.assign_attributes(attrs.merge(organization: org, password: PASSWORD))
  end
end

seed_user(org, role: "super_user", first_name: "Sam", last_name: "Super", email_address: "super@example.com")
seed_user(org, role: "admin", first_name: "Ada", last_name: "Admin", email_address: "admin@example.com")

maya = seed_user(org, role: "manager", first_name: "Maya", last_name: "Manager", email_address: "maya@example.com")
marco = seed_user(org, role: "manager", first_name: "Marco", last_name: "Manager", email_address: "marco@example.com")
# Maya covers Teams A and B; Marco covers Team C.
[ "Sales Team A", "Sales Team B" ].each { |t| TeamAccess.find_or_create_by!(user: maya, team: teams[t]) }
TeamAccess.find_or_create_by!(user: marco, team: teams["Sales Team C"])

FIRST_NAMES = %w[Alex Avery Blake Casey Devon Ellis Finley Gray Harper Indy Jules Kendall Lane Morgan Nico Oakley Parker Quinn Reese Sage Tatum Uma Val Wren].freeze
LAST_NAMES = %w[Archer Bellamy Calder Dunmore Ellery Fairbanks Garrity Holloway Iverson Jarrett Kincaid Lockhart Merritt Norwood Pryce Quillen Radcliffe Sutter Thorne Underhill Vance Whitlock Yardley Zeller].freeze

# 8 agents per team, 24 total
n = 0
teams.each_with_index do |(_name, team), ti|
  8.times do |i|
    first = FIRST_NAMES[n]
    last = LAST_NAMES[(n * 7 + 3) % LAST_NAMES.size]
    seed_user(org, role: "agent", team: team, first_name: first, last_name: last,
              email_address: "#{first.downcase}.#{last.downcase}@example.com",
              phone_agent_id: "#{%w[A B C][ti]}#{1001 + i}")
    n += 1
  end
end

# Eight colored statuses (fake phone codes) with the plan's default flags.
[ [ "Available", "ready", "#2f9e6f", nil, %w[Ready AVAIL] ],
  [ "On Call", "on_call", "#1f6fb2", nil, %w[InCall TALKING] ],
  [ "Wrap Up", "wrap_up", "#7e57c2", 3, %w[ACW WRAP] ],
  [ "Break", "break", "#e8883a", 15, %w[AUX-2 Break] ],
  [ "Lunch", "lunch", "#d9534f", 60, %w[AUX-3 Lunch] ],
  [ "Meeting", "meeting", "#8d6e63", nil, %w[AUX-4 Meeting] ],
  [ "Training", "other", "#26a69a", nil, %w[AUX-5 Training] ],
  [ "Offline", "offline", "#6c757d", nil, %w[LOGGEDOUT Offline] ]
].each_with_index do |(name, category, color, limit, codes), i|
  status = Status.find_or_initialize_by(organization: org, name: name)
  next unless status.new_record?
  status.assign_attributes({ category: category, color: color, time_limit_minutes: limit, sort_order: i + 1,
                             phone_codes_text: codes.join("\n") }.merge(Status.flag_defaults_for(category)))
  status.save_with_codes || raise("Couldn't seed #{name}: #{status.errors.full_messages.to_sentence}")
end

puts "Seeded #{Organization.count} org, #{Team.count} teams, #{User.count} users, #{Status.count} statuses (all fake)."
puts "Sign in as super@example.com, admin@example.com, maya@example.com or an agent (e.g. #{User.agent.first.email_address}) — password: #{PASSWORD}"
