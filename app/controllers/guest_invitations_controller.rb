# The guest-facing invitation. No account is needed: the 40-character token in the URL is the
# guest's credential, so these pages are never cached, indexed, or leaked via the Referer header.
class GuestInvitationsController < ApplicationController
  allow_unauthenticated_access
  layout "guest"

  skip_forgery_protection only: :unsubscribe # RFC 8058 one-click unsubscribe; the token authenticates
  before_action :set_private_headers
  before_action :set_guest

  rate_limit to: 20, within: 10.minutes, only: :rsvp, by: -> { "#{request.remote_ip}:#{params[:token].to_s.first(16)}" },
    with: -> { redirect_to guest_invitation_path(params[:token]), alert: "Too many attempts. Please wait a few minutes and try again." }
  rate_limit to: 120, within: 1.minute, by: -> { request.remote_ip }, name: "guest-pages",
    with: -> { head :too_many_requests }

  def show
    @rsvp = RsvpSubmission.from_guest(@guest)
    @guest.record_view! unless host_viewing?
    load_updates
  end

  def rsvp
    @rsvp = RsvpSubmission.new(rsvp_params.merge(guest: @guest))
    if @rsvp.save
      redirect_to guest_invitation_path(params[:token]), notice: thank_you_message
    else
      @show_form = true
      load_updates
      render :show, status: :unprocessable_content
    end
  end

  def calendar
    invite = CalendarInvite.new(@event, url: guest_invitation_url(params[:token]))
    send_data invite.to_ics, filename: invite.filename, type: "text/calendar; charset=utf-8", disposition: "attachment"
  end

  def unsubscribe
    @guest.update!(unsubscribed_at: Time.current) unless @guest.unsubscribed?
    respond_to do |format|
      format.html { redirect_to guest_invitation_path(params[:token]), notice: "You won't receive more messages about this event. Your RSVP is unchanged." }
      format.any { head :ok }
    end
  end

  private
    def set_guest
      @guest = Guest.find_by_access_token(params[:token])
      return render("invalid_link", status: :not_found) unless @guest

      @event = @guest.event
      render("unavailable", status: :not_found) if @event.draft?
    end

    def set_private_headers
      response.headers["Referrer-Policy"] = "no-referrer"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.headers["Cache-Control"] = "private, no-store"
    end

    def rsvp_params
      permitted = params.fetch(:rsvp, {}).permit(:status, :party_size, :guest_note, answers: {})
      permitted.to_h.symbolize_keys
    end

    # Viewing your own event's guest link (e.g. to test it) shouldn't count as the guest opening it.
    def host_viewing?
      resume_session && @event.role_for(Current.user).present?
    end

    def load_updates
      @updates = @event.messages.for_guests.where(status: "dispatched").order(dispatched_at: :desc).select do |message|
        message.deliveries.exists?(guest_id: @guest.id) || message.audience.guests.exists?(@guest.id)
      end
    end

    def thank_you_message
      case @rsvp.status
      when "yes" then "Wonderful — you're on the list! We've saved your RSVP."
      when "maybe" then "Thanks for letting the host know. You can update your RSVP any time before the deadline."
      else "Thanks for letting the host know. Your RSVP is saved."
      end
    end
end
