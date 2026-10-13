# Updates and reminders to chosen guests, by email and/or SMS, now or at a scheduled time.
class MessagesController < ApplicationController
  include EventScoped
  before_action { authorize! :send_messages }
  before_action :set_message, only: %i[show destroy retry_failed]
  rate_limit to: 30, within: 1.hour, only: :create, by: -> { current_user.id },
    with: -> { redirect_to event_messages_path(params[:event_id]), alert: "Too many messages in a short time. Please wait a bit." }

  COMPOSABLE_KINDS = %w[update reminder].freeze

  def index
    @messages = @event.messages.where.not(kind: "rsvp_confirmation").includes(:author).order(created_at: :desc)
    @counts = Delivery.where(message_id: @messages.map(&:id)).group(:message_id, :status).count
  end

  def new
    @message = @event.messages.new(kind: "update", channels: %w[email], audience: {})
    apply_preset(params[:preset])
  end

  def create
    return redirect_to(event_path(@event), alert: "Publish the event before messaging guests.") if @event.draft?

    if (existing = @event.messages.find_by(idempotency_key: idempotency_key))
      return redirect_to(event_message_path(@event, existing), notice: "That message was already sent.")
    end

    @message = @event.messages.new(message_params)
    @message.assign_attributes(author: current_user, idempotency_key: idempotency_key, status: scheduling? ? "scheduled" : "draft")
    @message.scheduled_for_local = nil unless scheduling?

    if !@message.scheduled? && @message.valid? && @message.recipients.none?
      @message.errors.add(:base, "No one would receive this: no invited guests match these filters with an email address#{' or phone' if @message.channels.include?('sms')}. Invite them first, or widen the filters.")
      return render(:new, status: :unprocessable_content)
    end

    if @message.save
      if @message.scheduled?
        @message.enqueue_scheduled_dispatch
        notice = "Scheduled for #{@event.local(@message.scheduled_for).strftime('%b %-d at %-l:%M %p %Z')} — #{helpers.pluralize(@message.recipients.count, 'guest')} currently match."
      else
        @message.dispatch!
        notice = "Sending to #{helpers.pluralize(@message.recipients_count, 'guest')}."
      end
      redirect_to event_message_path(@event, @message), notice: notice
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @deliveries = @message.deliveries.includes(:guest).order(:status, :id)
  end

  # Cancels a message that hasn't gone out yet.
  def destroy
    if @message.scheduled?
      @message.destroy!
      # Cancelling an automatic reminder turns that reminder off, so a later date change won't revive it.
      setting = { AutoReminders::NUDGE_KEY => :auto_nudge, AutoReminders::DAY_BEFORE_KEY => :auto_day_before }[@message.idempotency_key]
      @event.update_columns(setting => false) if setting
      redirect_to event_messages_path(@event), notice: "Scheduled message cancelled.", status: :see_other
    else
      redirect_to event_message_path(@event, @message), alert: "Only scheduled messages can be cancelled."
    end
  end

  def retry_failed
    count = @message.deliveries.where(status: "failed").count { |delivery| delivery.retry! }
    redirect_to event_message_path(@event, @message), notice: "Retrying #{helpers.pluralize(count, 'failed delivery')}."
  end

  # Live "this will reach N guests" count for the compose form.
  def audience_count
    message = @event.messages.new(message_params.merge(idempotency_key: "preview"))
    matching = message.audience.guests
    reachable = message.channels.any? ? message.recipients.count : 0
    render json: { reachable: reachable, matching: matching.count, unreachable: matching.count - reachable }
  end

  private
    def set_message
      @message = @event.messages.find(params[:id])
    end

    def message_params
      permitted = params.fetch(:message, {}).permit(:kind, :subject, :body, :scheduled_for_local,
        channels: [], audience: { statuses: [], groups: [] })
      permitted[:kind] = permitted[:kind].presence_in(COMPOSABLE_KINDS) || "update"
      permitted[:audience] = (permitted[:audience] || {}).to_h
      permitted[:channels] = Array(permitted[:channels]).compact_blank
      permitted
    end

    def scheduling?
      params[:send_at] == "later"
    end

    def idempotency_key
      key = params[:idempotency_key].to_s
      @idempotency_key ||= key.match?(/\A[A-Za-z0-9-]{8,64}\z/) ? key : SecureRandom.uuid
    end

    def apply_preset(preset)
      case preset
      when "nudge"
        deadline = @event.rsvp_deadline ? " by #{@event.local(@event.rsvp_deadline).strftime('%A, %B %-d')}" : ""
        @message.assign_attributes(kind: "reminder", audience: { "statuses" => [ "pending" ] },
          subject: "Can you make it to #{@event.title}?",
          body: "Just a friendly nudge — #{@event.display_host_name} would love to know if you can come. Please RSVP#{deadline} using the button below.")
      when "day_before"
        @message.assign_attributes(kind: "reminder", audience: { "statuses" => %w[yes maybe] },
          subject: "See you soon at #{@event.title}",
          body: "Looking forward to seeing you! Here are the details again — the button below has directions and calendar links.")
        @message.scheduled_for_local = (@event.local(@event.starts_at) - 1.day).strftime("%Y-%m-%dT%H:%M") if @event.starts_at && @event.starts_at - 1.day > Time.current
      end
    end
end
