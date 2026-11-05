module Board
  # Pushes board changes to everyone watching, over Turbo Streams.
  #
  # Streams (the page asks for the ones its viewer may see; names are signed, so they can't be guessed):
  #   [organization, :board]  - admins and above: every agent
  #   [team, :board]          - managers: the teams they were granted
  #   [user, :status]         - one person's own page
  class Broadcaster
    # An agent's status changed: swap just their row (a few hundred bytes) on every board that shows them.
    def self.status_changed(user)
      new(user).status_changed
    rescue StandardError => e # a failed broadcast must never lose the event itself
      Rails.logger.error("Board broadcast failed for user #{user.id}: #{e.class}: #{e.message}")
    end

    # People or teams were added, moved, renamed or deactivated: have those boards reload (they re-sort themselves).
    def self.roster_changed(organization, *teams)
      Turbo::StreamsChannel.broadcast_refresh_to([ organization, :board ])
      teams.flatten.compact.uniq.each { |team| Turbo::StreamsChannel.broadcast_refresh_to([ team, :board ]) }
    rescue StandardError => e
      Rails.logger.error("Board refresh failed: #{e.class}: #{e.message}")
    end

    def initialize(user)
      @user = user
    end

    def status_changed
      return unless @user.agent? && @user.active?
      Time.use_zone(@user.organization.timezone) do
        row = Snapshot.rows_for([ @user ]).first
        streams.each do |stream|
          Turbo::StreamsChannel.broadcast_replace_to(stream, target: ActionView::RecordIdentifier.dom_id(@user, :board_row),
                                                     partial: "board/row", locals: { row: row })
        end
        Turbo::StreamsChannel.broadcast_refresh_to([ @user, :status ])
      end
    end

    private

    def streams
      [ [ @user.organization, :board ], (@user.team ? [ @user.team, :board ] : nil) ].compact
    end
  end
end
