# Super User screen: the phone-system webhook, its API key, and the events we couldn't place.
class IntegrationsController < ApplicationController
  before_action { authorize :organization, :manage_integration? }

  def show
    load_screen
  end

  # Replaces the key. The new one is shown on this response only, never stored readable.
  def regenerate_key
    @new_key = current_user.organization.generate_api_key!
    AuditLog.record!(current_user, "api_key_regenerated", current_user.organization)
    load_screen
    render :show
  end

  # An unmapped phone code -> the status it should mean from now on.
  def map_code
    organization = current_user.organization
    status = organization.statuses.find(params[:status_id])
    code = params[:phone_code].to_s.strip
    status.phone_codes_text = (status.phone_code_list + [ code ]).join("\n")
    if status.save_with_codes
      organization.unmatched_events.unmapped_codes.unresolved.where(phone_code: code).update_all(resolved_at: Time.current)
      AuditLog.record!(current_user, "mapped_code", status, "phone_code" => code)
      redirect_to integration_path, notice: "“#{code}” now means #{status.name}. Events already received stay as Unmapped."
    else
      redirect_to integration_path, alert: status.errors.full_messages.to_sentence
    end
  end

  # An unknown phone agent ID -> the agent it belongs to. Held events are then replayed in time order.
  def link_agent
    organization = current_user.organization
    user = organization.users.find(params[:user_id])
    phone_id = params[:phone_agent_id].to_s.strip
    unless user.update(phone_agent_id: phone_id)
      return redirect_to(integration_path, alert: user.errors.full_messages.to_sentence)
    end
    held = organization.unmatched_events.unknown_agents.unresolved.where(phone_agent_id: phone_id).order(:occurred_at, :id)
    ingest = StatusEvents::Ingest.new(organization)
    replayed = held.map do |event|
      ingest.call(event.payload).tap { event.resolve! }
    end
    AuditLog.record!(current_user, "linked_phone_id", user, "phone_agent_id" => phone_id, "events_replayed" => replayed.size)
    redirect_to integration_path, notice: "#{phone_id} is now #{user.full_name}. Replayed #{helpers.pluralize(replayed.size, 'held event')}."
  end

  private

  def load_screen
    organization = current_user.organization
    @organization = organization
    @webhook_url = api_v1_status_events_url
    @unmapped_codes = organization.unmatched_events.unmapped_codes.unresolved.group(:phone_code).order(Arel.sql("count(*) desc")).count
    @unknown_ids = organization.unmatched_events.unknown_agents.unresolved.group(:phone_agent_id).order(Arel.sql("count(*) desc")).count
    @statuses = organization.statuses.active.ordered
    @people = organization.users.active.order(:last_name, :first_name)
    @last_phone_event_at = StatusEvent.joins(:user).where(users: { organization_id: organization.id }, source: "phone").maximum(:created_at)
  end
end
