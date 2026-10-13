# "Send invitations" on the event dashboard: emails every guest who hasn't been invited yet.
# The form embeds a one-time idempotency key, so double clicks and retried requests are no-ops.
class InvitationSendsController < ApplicationController
  include EventScoped
  before_action { authorize! :send_messages }
  rate_limit to: 20, within: 1.hour, by: -> { current_user.id }, with: -> { redirect_to event_path(params[:event_id]), alert: "Too many sends in a short time. Please wait a bit." }

  def create
    return redirect_to(event_path(@event), alert: "Publish the event before sending invitations.") unless @event.published?

    attributes = { kind: "invitation", author: current_user, channels: channels, audience: {},
                   body: params[:personal_note].to_s.strip.first(1000).presence }
    return schedule(attributes) if params[:send_at] == "later"

    message = @event.messages.idempotent_create!(idempotency_key: idempotency_key, **attributes)

    if message.status == "dispatched"
      redirect_to event_guests_path(@event), notice: "Those invitations were already sent."
    else
      message.dispatch!
      redirect_to event_guests_path(@event), notice: sent_notice(message)
    end
  end

  private
    def schedule(attributes)
      message = @event.messages.find_by(idempotency_key: idempotency_key) ||
        @event.messages.new(idempotency_key: idempotency_key, status: "scheduled", scheduled_for_local: params[:scheduled_for_local], **attributes)
      if message.persisted? || message.save
        message.enqueue_scheduled_dispatch if message.previously_new_record?
        redirect_to event_messages_path(@event), notice: "Invitations scheduled for #{helpers.message_status_text(message).delete_prefix('Scheduled for ')}."
      else
        redirect_to event_path(@event), alert: "Couldn't schedule: #{message.errors.full_messages.to_sentence}."
      end
    end

    def channels
      requested = Array(params[:channels]).map(&:to_s) & Message::CHANNELS
      requested -= [ "sms" ] unless Messaging.sms_enabled?
      requested.presence || %w[email]
    end

    def idempotency_key
      key = params[:idempotency_key].to_s
      key.match?(/\A[A-Za-z0-9-]{8,64}\z/) ? key : SecureRandom.uuid
    end

    def sent_notice(message)
      count = message.recipients_count
      return "Everyone who can be reached has already been invited." if count.zero?

      "Sending #{count} #{'invitation'.pluralize(count)}. Delivery status updates in the guest list."
    end
end
