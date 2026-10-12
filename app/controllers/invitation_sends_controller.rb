# "Send invitations" on the event dashboard: emails every guest who hasn't been invited yet.
# The form embeds a one-time idempotency key, so double clicks and retried requests are no-ops.
class InvitationSendsController < ApplicationController
  include EventScoped
  before_action { authorize! :send_messages }
  rate_limit to: 20, within: 1.hour, by: -> { current_user.id }, with: -> { redirect_to event_path(params[:event_id]), alert: "Too many sends in a short time. Please wait a bit." }

  def create
    return redirect_to(event_path(@event), alert: "Publish the event before sending invitations.") unless @event.published?

    message = @event.messages.create_or_find_by!(idempotency_key: idempotency_key) do |m|
      m.assign_attributes(kind: "invitation", author: current_user, channels: %w[email], audience: {},
        body: params[:personal_note].to_s.strip.first(1000).presence)
    end

    if message.status == "dispatched"
      redirect_to event_path(@event, anchor: "guests"), notice: "Those invitations were already sent."
    else
      message.dispatch!
      redirect_to event_path(@event, anchor: "guests"), notice: sent_notice(message)
    end
  end

  private
    def idempotency_key
      key = params[:idempotency_key].to_s
      key.match?(/\A[A-Za-z0-9-]{8,64}\z/) ? key : SecureRandom.uuid
    end

    def sent_notice(message)
      count = message.recipients_count
      return "Everyone with an email address has already been invited." if count.zero?

      "Sending #{count} #{'invitation'.pluralize(count)}. Delivery status updates in the guest list."
    end
end
