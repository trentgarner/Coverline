# Drives fake agents through believable status changes for demos and testing, with no phone
# system involved. The logic lives here (no network) so it can be tested; bin/simulate sends
# the events to the webhook.
class StatusSimulator
  Agent = Struct.new(:phone_id, :state, keyword_init: true)

  # Where an agent goes next, by what they're doing now: [status name, weight].
  TRANSITIONS = {
    "Offline"   => [ [ "Available", 1 ] ],
    "Available" => [ [ "On Call", 70 ], [ "Break", 6 ], [ "Lunch", 3 ], [ "Meeting", 3 ], [ "Training", 2 ], [ "Offline", 1 ] ],
    "On Call"   => [ [ "Wrap Up", 85 ], [ "Available", 15 ] ],
    "Wrap Up"   => [ [ "Available", 90 ], [ "On Call", 10 ] ],
    "Break"     => [ [ "Available", 1 ] ],
    "Lunch"     => [ [ "Available", 1 ] ],
    "Meeting"   => [ [ "Available", 1 ] ],
    "Training"  => [ [ "Available", 1 ] ]
  }.freeze

  # codes: { "Available" => "Ready", "Break" => "AUX-2", ... } (a phone code per status name)
  def initialize(phone_ids:, codes:, random: Random.new, start: "Offline")
    @codes = codes
    @random = random
    @agents = phone_ids.map { |id| Agent.new(phone_id: id, state: start) }
  end

  attr_reader :agents

  # Moves `count` random agents to their next status and returns the events to send.
  def step(count: 1, now: Time.current)
    @agents.sample(count, random: @random).filter_map do |agent|
      choices = TRANSITIONS.fetch(agent.state, [ [ "Available", 1 ] ]).select { |name, _| @codes.key?(name) }
      next if choices.empty?
      agent.state = pick(choices)
      { agent_id: agent.phone_id, status_code: @codes.fetch(agent.state), occurred_at: now.utc.iso8601, event_id: "sim-#{SecureRandom.uuid}" }
    end
  end

  private

  def pick(choices)
    roll = @random.rand(choices.sum { |_, w| w })
    choices.each { |name, weight| return name if (roll -= weight) < 0 }
    choices.last.first
  end
end
