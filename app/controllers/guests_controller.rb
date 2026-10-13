class GuestsController < ApplicationController
  include EventScoped
  before_action { authorize! :manage_guests }
  before_action :set_guest, except: %i[index new create export bulk]

  GUESTS_PER_PAGE = 100

  def index
    @summary = @event.rsvp_summary
    @query = params[:q].to_s.strip
    @status_filter = params[:status].presence_in(Guest::RSVP_STATUSES)
    @group_filter = params[:group].presence
    guests = @event.guests.order(:name)
    guests = guests.search(@query) if @query.present?
    guests = guests.where(rsvp_status: @status_filter) if @status_filter
    guests = guests.where(group_name: @group_filter) if @group_filter
    @page = [ params[:page].to_i, 1 ].max
    @total_pages = [ (guests.count / GUESTS_PER_PAGE.to_f).ceil, 1 ].max
    @page = [ @page, @total_pages ].min
    @guests = guests.includes(:rsvp_answers, :payments, deliveries: :message).limit(GUESTS_PER_PAGE).offset((@page - 1) * GUESTS_PER_PAGE)
    @questions = @event.questions.to_a
  end

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
        redirect_to event_guests_path(@event), notice: "#{@guest.name} added to the guest list."
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
      redirect_to event_guests_path(@event), notice: "#{@guest.name} updated."
    else
      @rsvp = RsvpSubmission.from_guest(@guest)
      render :edit, status: :unprocessable_content
    end
  end

  # Host records or corrects a response on the guest's behalf (deadline and capacity don't apply).
  def rsvp
    @rsvp = RsvpSubmission.new(rsvp_params.merge(guest: @guest, by_host: true, user: current_user))
    if @rsvp.save
      redirect_to event_guests_path(@event), notice: "RSVP for #{@guest.name} saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @guest.destroy!
    redirect_to event_guests_path(@event), notice: "#{@guest.name} removed from the guest list.", status: :see_other
  end

  # Sends this guest a fresh copy of the invitation, even if one was already delivered.
  def resend
    authorize! :send_messages
    return redirect_to(event_path(@event), alert: "Publish the event before sending invitations.") unless @event.published?
    return redirect_to(event_path(@event), alert: "#{@guest.name} has no email address (or has unsubscribed).") unless @guest.emailable?

    message = @event.messages.idempotent_create!(idempotency_key: params[:idempotency_key].presence || SecureRandom.uuid,
      kind: "invitation", author: current_user, channels: %w[email], audience: { "guest_ids" => [ @guest.id ], "resend" => true })
    message.dispatch! unless message.status == "dispatched"
    redirect_to event_guests_path(@event), notice: "Invitation re-sent to #{@guest.name}."
  end

  def export
    authorize! :view_contacts
    send_data GuestListExport.new(@event).to_csv,
      filename: "#{@event.title.parameterize.presence || 'event'}-guests-#{Date.current.iso8601}.csv", type: "text/csv"
  end

  # Applies one action to the guests ticked in the guest list.
  def bulk
    guests = @event.guests.where(id: Array(params[:guest_ids]).map(&:to_i))
    return redirect_to(event_guests_path(@event), alert: "Select at least one guest first.") if guests.none?

    notice = case params[:bulk_action]
    when "group"
      group = params[:group_name].to_s.squish.first(60).presence
      count = guests.update_all(group_name: group, updated_at: Time.current)
      group ? "Moved #{pluralize_guests(count)} to “#{group}”." : "Cleared the group for #{pluralize_guests(count)}."
    when "invite"
      authorize! :send_messages
      return redirect_to(event_path(@event), alert: "Publish the event before sending invitations.") unless @event.published?

      message = @event.messages.idempotent_create!(idempotency_key: params[:idempotency_key].presence || SecureRandom.uuid,
        kind: "invitation", author: current_user, channels: %w[email], audience: { "guest_ids" => guests.ids })
      message.dispatch! unless message.status == "dispatched"
      skipped = guests.count - message.recipients_count
      "Sending #{message.recipients_count} #{'invitation'.pluralize(message.recipients_count)}." +
        (skipped.positive? ? " #{pluralize_guests(skipped)} skipped (already invited, no email, or unsubscribed)." : "")
    when "remove"
      "Removed #{pluralize_guests(guests.destroy_all.size)}."
    else
      return redirect_to(event_guests_path(@event), alert: "Choose an action.")
    end
    redirect_to event_guests_path(@event), notice: notice, status: :see_other
  end

  private
    def pluralize_guests(count)
      helpers.pluralize(count, "guest")
    end

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
