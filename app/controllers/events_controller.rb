class EventsController < ApplicationController
  include EventScoped
  skip_before_action :set_event, only: %i[index new create]

  GUESTS_PER_PAGE = 100

  def index
    events = current_user.accessible_events.includes(:owner)
    @upcoming = events.where.not(status: "cancelled").upcoming
    @past = events.past.limit(20)
    @cancelled = events.cancelled.order(updated_at: :desc).limit(20)
  end

  def show
    authorize! :view
    # Door staff only need the door: names and party sizes, nothing else.
    return redirect_to(event_check_in_path(@event)) if policy.role == "checkin"
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
    @guests = guests.includes(:rsvp_answers, deliveries: :message).limit(GUESTS_PER_PAGE).offset((@page - 1) * GUESTS_PER_PAGE)
    @questions = @event.questions.to_a
    @activities = @event.activities.recent.includes(:guest, :user).limit(12)
    @uninvited_count = invitation_preview.recipients.count
    @recent_messages = @event.messages.where.not(kind: "rsvp_confirmation").order(created_at: :desc).limit(3)
  end

  def new
    @event = current_user.owned_events.new(time_zone: params[:time_zone].presence || "America/New_York", host_name: current_user.name)
  end

  def create
    @event = current_user.owned_events.new(event_params)
    if @event.save
      Activity.record(event: @event, user: current_user, action: "event_created")
      redirect_to edit_event_design_path(@event), notice: "Event created as a draft. Next, make the invitation yours."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize! :edit
  end

  def update
    authorize! :edit
    if @event.update(event_params)
      @event.touch_calendar! if @event.published? && @event.calendar_details_changed?
      redirect_to @event, notice: update_notice
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize! :destroy
    @event.destroy!
    redirect_to events_path, notice: "“#{@event.title}” and its guest list were deleted.", status: :see_other
  end

  def publish
    authorize! :publish
    if @event.publish
      Activity.record(event: @event, user: current_user, action: "event_published")
      redirect_to @event, notice: "Published! Your invitation links are live."
    else
      redirect_to edit_event_path(@event), alert: "Before publishing: #{@event.errors.full_messages.to_sentence}."
    end
  end

  def cancellation
    authorize! :cancel
  end

  def cancel
    authorize! :cancel
    was_published = @event.published?
    if @event.cancel(note: params[:cancellation_note])
      Activity.record(event: @event, user: current_user, action: "event_cancelled")
      notified = notify_cancellation if was_published && params[:notify_guests] == "1"
      redirect_to @event, notice: [ "Event cancelled.", (notified ? "Guests who were invited are being notified." : nil) ].compact.join(" ")
    else
      redirect_to @event, alert: "This event was already cancelled."
    end
  end

  def duplicate
    authorize! :edit
    copy = @event.duplicate(include_guests: params[:include_guests] == "1")
    copy.update!(owner: current_user) unless copy.owner_id == current_user.id
    redirect_to edit_event_path(copy), notice: "Duplicated. You're now editing the copy (a draft)."
  end

  # Revokes the current public share link and issues a new one.
  def regenerate_share_link
    authorize! :edit
    @event.regenerate_share_token!
    redirect_to event_path(@event, anchor: "share"), notice: "New share link created. The old link no longer works."
  end

  # The host's view of the guest-facing invitation, using a sample guest.
  def preview
    authorize! :view
    @guest = Guest.new(event: @event, name: "Guest Name", plus_ones_allowed: @event.default_plus_ones, token_key: "preview")
    @rsvp = RsvpSubmission.new(guest: @guest, party_size: 1)
    @preview = true
    @updates = []
    render "guest_invitations/show", layout: "guest"
  end

  private
    def event_params
      params.expect(event: %i[
        title host_name description starts_at_local ends_at_local time_zone location_name address video_url
        rsvp_deadline_local capacity allow_maybe default_plus_ones allow_link_rsvp show_guest_count
      ])
    end

    def invitation_preview
      @event.messages.new(kind: "invitation", channels: Messaging.sms_enabled? ? %w[email sms] : %w[email], audience: {})
    end

    def update_notice
      notice = "Event saved."
      if @event.published? && @event.calendar_details_changed? && @event.guests.where.not(invited_at: nil).exists?
        notice += " The date, time or place changed — consider sending guests an update."
      end
      notice
    end

    def notify_cancellation
      message = @event.messages.idempotent_create!(idempotency_key: "cancellation-#{@event.id}", kind: "cancellation",
        author: current_user, channels: %w[email], subject: "Cancelled: #{@event.title}", body: @event.cancellation_note, audience: {})
      message.dispatch! unless message.status == "dispatched"
      true
    end
end
