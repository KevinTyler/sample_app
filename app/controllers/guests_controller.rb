class GuestsController < ApplicationController
  include EventScoped
  before_action { authorize! :manage_guests }
  before_action :set_guest, except: %i[new create]

  def new
    @guest = @event.guests.new(plus_ones_allowed: @event.default_plus_ones)
  end

  def create
    @guest = @event.guests.new(guest_params.merge(source: "manual"))
    if @guest.save
      Activity.record(event: @event, guest: @guest, user: current_user, action: "guest_added")
      if params[:add_another]
        redirect_to new_event_guest_path(@event), notice: "#{@guest.name} added. Add the next guest below."
      else
        redirect_to event_path(@event, anchor: "guests"), notice: "#{@guest.name} added to the guest list."
      end
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @rsvp = RsvpSubmission.from_guest(@guest)
  end

  def update
    if @guest.update(guest_params)
      redirect_to event_path(@event, anchor: "guests"), notice: "#{@guest.name} updated."
    else
      @rsvp = RsvpSubmission.from_guest(@guest)
      render :edit, status: :unprocessable_content
    end
  end

  # Host records or corrects a response on the guest's behalf (deadline and capacity don't apply).
  def rsvp
    @rsvp = RsvpSubmission.new(rsvp_params.merge(guest: @guest, by_host: true, user: current_user))
    if @rsvp.save
      redirect_to event_path(@event, anchor: "guests"), notice: "RSVP for #{@guest.name} saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @guest.destroy!
    redirect_to event_path(@event, anchor: "guests"), notice: "#{@guest.name} removed from the guest list.", status: :see_other
  end

  # Sends this guest a fresh copy of the invitation, even if one was already delivered.
  def resend
    authorize! :send_messages
    return redirect_to(event_path(@event), alert: "Publish the event before sending invitations.") unless @event.published?
    return redirect_to(event_path(@event), alert: "#{@guest.name} has no email address (or has unsubscribed).") unless @guest.emailable?

    message = @event.messages.idempotent_create!(idempotency_key: params[:idempotency_key].presence || SecureRandom.uuid,
      kind: "invitation", author: current_user, channels: %w[email], audience: { "guest_ids" => [ @guest.id ], "resend" => true })
    message.dispatch! unless message.status == "dispatched"
    redirect_to event_path(@event, anchor: "guests"), notice: "Invitation re-sent to #{@guest.name}."
  end

  private
    def set_guest
      @guest = @event.guests.find(params[:id])
    end

    def guest_params
      params.expect(guest: %i[name email phone group_name plus_ones_allowed host_notes])
    end

    def rsvp_params
      params.fetch(:rsvp, {}).permit(:status, :party_size, :guest_note, answers: {}).to_h.symbolize_keys
    end
end
