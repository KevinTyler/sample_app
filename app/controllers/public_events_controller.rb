# The event's public share link (/e/<share token>): the invitation without any guest data and,
# if the host enabled open RSVPs, a form that adds the visitor to the guest list.
class PublicEventsController < ApplicationController
  allow_unauthenticated_access
  layout "guest"

  before_action :set_event
  rate_limit to: 8, within: 1.hour, only: :rsvp, by: -> { request.remote_ip },
    with: -> { redirect_to public_event_path(params[:share_token]), alert: "Too many RSVPs from this connection. Please try again later." }
  rate_limit to: 120, within: 1.minute, by: -> { request.remote_ip }, name: "public-pages", with: -> { head :too_many_requests }

  def show
    @rsvp = LinkRsvp.new(event: @event, party_size: 1)
  end

  def rsvp
    return redirect_to(public_event_path(params[:share_token]), alert: "RSVPs for this event are by invitation.") unless open_rsvp?

    @rsvp = LinkRsvp.new(rsvp_params.merge(event: @event))
    if @rsvp.save
      if @rsvp.outcome == :created
        redirect_to guest_invitation_path(@rsvp.guest.access_token),
          notice: "Your RSVP is saved! We've emailed you this personal link so you can change it later."
      else
        redirect_to public_event_path(params[:share_token]),
          notice: "You're already on the guest list — we've emailed your personal RSVP link to that address."
      end
    else
      render :show, status: :unprocessable_content
    end
  end

  def calendar
    invite = CalendarInvite.new(@event, url: public_event_url(params[:share_token]), include_private: false)
    send_data invite.to_ics, filename: invite.filename, type: "text/calendar; charset=utf-8", disposition: "attachment"
  end

  private
    def set_event
      @event = Event.find_by(share_token: params[:share_token])
      return render("guest_invitations/invalid_link", status: :not_found) unless @event
      return render("guest_invitations/unavailable", status: :not_found) if @event.draft?

      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.headers["Referrer-Policy"] = "no-referrer"
    end

    def open_rsvp?
      @event.allow_link_rsvp && @event.accepting_rsvps?
    end
    helper_method :open_rsvp?

    def rsvp_params
      params.fetch(:rsvp, {}).permit(:name, :email, :status, :party_size, :guest_note, answers: {}).to_h.symbolize_keys
    end
end
