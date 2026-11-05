module Api
  module V1
    # The phone system's webhook. POST one event or a batch:
    #   { "agent_id": "A1001", "status_code": "AUX-2", "occurred_at": "2026-11-01T15:04:05Z", "event_id": "abc-123" }
    #   { "events": [ {...}, {...} ] }
    # Authenticated with the organization's API key: Authorization: Bearer cvl_...
    class StatusEventsController < ActionController::API
      MAX_BATCH = 500

      before_action :authenticate_with_api_key

      def create
        events = params[:events].presence || [ params ]
        return render(json: { error: "Send an event, or { \"events\": [...] }." }, status: :unprocessable_entity) unless events.is_a?(Array)
        return render(json: { error: "At most #{MAX_BATCH} events per request." }, status: :content_too_large) if events.size > MAX_BATCH

        ingest = StatusEvents::Ingest.new(@organization)
        results = events.map do |event|
          payload = event.respond_to?(:to_unsafe_h) ? event.to_unsafe_h : event.to_h
          ingest.call(payload.slice("agent_id", "status_code", "occurred_at", "event_id")).to_h.compact
        end
        render json: { results: results }
      end

      private

      def authenticate_with_api_key
        key = request.authorization.to_s[/\ABearer\s+(\S+)\z/, 1]
        @organization = Organization.find_by_api_key(key)
        render json: { error: "Missing or invalid API key." }, status: :unauthorized unless @organization
      end
    end
  end
end
