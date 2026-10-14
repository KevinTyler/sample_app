# Every guest-facing email (invitation, update, reminder, cancellation) for one Delivery, written in
# the event's language.
class GuestMailer < ApplicationMailer
  helper :events

  def notice
    @delivery = params[:delivery]
    @message = @delivery.message
    @event = @message.event
    @guest = @delivery.guest
    @design = InvitationDesign.for(@event)
    @url = @delivery.personal_url
    @unsubscribe_url = guest_unsubscribe_url(@guest.access_token, **Messaging.url_options)

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    headers["X-Entity-Ref-ID"] = "delivery-#{@delivery.id}"

    if @event.starts_at && @message.kind.in?(%w[invitation update cancellation rsvp_confirmation])
      invite = CalendarInvite.new(@event, url: @url)
      attachments[invite.filename] = { mime_type: "text/calendar", content: invite.to_ics }
    end

    I18n.with_locale(@event.locale.presence || I18n.default_locale) do
      mail(
        to: email_address_with_name(@delivery.recipient, @guest.name),
        from: email_address_with_name(sender_address, "#{@event.display_host_name} via Cordially"),
        reply_to: @event.owner.email_address,
        subject: @message.subject_line,
        # A stable Message-ID per delivery lets mail servers and providers recognize a retry.
        message_id: "<delivery-#{@delivery.id}-#{@delivery.created_at.to_i}@#{message_id_domain}>"
      )
    end
  end

  private
    def sender_address
      Mail::Address.new(ApplicationMailer.from_address).address
    end

    def message_id_domain
      sender_address.split("@").last
    end
end
