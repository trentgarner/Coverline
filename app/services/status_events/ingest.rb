module StatusEvents
  # Turns one phone-system event into a recorded status change, applying section 5's rules:
  # find the agent by phone ID, map the phone code to a status, and keep anything we can't
  # place so an admin can fix it. Safe to call again with the same event (retries).
  class Ingest
    Result = Struct.new(:event_id, :outcome, :detail, keyword_init: true)
    # outcomes: recorded duplicate unmapped_code unknown_agent inactive_agent invalid

    def initialize(organization)
      @organization = organization
    end

    def call(payload)
      payload = payload.to_h.stringify_keys
      agent_id = payload["agent_id"].to_s.strip
      code = payload["status_code"].to_s.strip
      event_id = payload["event_id"].to_s.strip
      at = parse_time(payload["occurred_at"])

      return invalid(event_id, "event_id is required (it makes retries safe)") if event_id.blank?
      return invalid(event_id, "agent_id is required") if agent_id.blank?
      return invalid(event_id, "status_code is required") if code.blank?
      return invalid(event_id, "occurred_at must be an ISO 8601 time, e.g. 2026-11-01T15:04:05Z") unless at

      user = @organization.users.find_by(phone_agent_id: agent_id)
      return hold_for_admin("unknown_agent", payload, event_id, at) unless user
      return Result.new(event_id: event_id, outcome: :inactive_agent, detail: "#{user.full_name} is deactivated; event ignored") unless user.active?

      status = status_for(code)
      mapped = status.present?
      status ||= @organization.unmapped_status

      recorded = Recorder.call(user: user, status: status, at: at, source: "phone", external_event_id: event_id)
      return Result.new(event_id: event_id, outcome: :duplicate) if recorded.outcome == :duplicate

      note_unmapped_code(payload, event_id, at) unless mapped
      Result.new(event_id: event_id, outcome: mapped ? :recorded : :unmapped_code,
                 detail: mapped ? nil : "no status maps to code “#{code}”; recorded as Unmapped")
    rescue Recorder::InvalidTime => e
      invalid(event_id, e.message)
    end

    private

    # Case-insensitive code lookup. A code that points at a deactivated status counts as unmapped.
    def status_for(code)
      @organization.statuses.active.joins(:status_codes).where("lower(status_codes.phone_code) = ?", code.downcase).first
    end

    def hold_for_admin(reason, payload, event_id, at)
      record_unmatched(reason, payload, event_id, at)
      Result.new(event_id: event_id, outcome: :unknown_agent, detail: "no agent has phone ID “#{payload['agent_id']}”; held for an admin to link")
    end

    def note_unmapped_code(payload, event_id, at) = record_unmatched("unmapped_code", payload, event_id, at)

    def record_unmatched(reason, payload, event_id, at)
      @organization.unmatched_events.find_or_create_by!(reason: reason, external_event_id: event_id) do |u|
        u.phone_agent_id = payload["agent_id"].to_s.strip
        u.phone_code = payload["status_code"].to_s.strip
        u.occurred_at = at
        u.payload = payload.slice("agent_id", "status_code", "occurred_at", "event_id")
      end
    rescue ActiveRecord::RecordNotUnique
      nil # a retry of an event we already hold
    end

    def invalid(event_id, detail) = Result.new(event_id: event_id.presence, outcome: :invalid, detail: detail)

    def parse_time(value)
      return nil if value.blank?
      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
