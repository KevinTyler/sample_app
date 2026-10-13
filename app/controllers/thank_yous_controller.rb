# Thank-you notes: kids record a photo or video for each gift (straight from the phone camera),
# parents add a written note, then send each one by text or email — or share it from their own phone.
class ThankYousController < ApplicationController
  include EventScoped
  before_action { authorize! :manage_guests }
  before_action :set_thank_you, only: %i[edit update destroy deliver mark_sent]
  rate_limit to: 60, within: 1.hour, only: %i[deliver deliver_all], by: -> { current_user.id },
    with: -> { redirect_to event_thank_yous_path(params[:event_id]), alert: "That's a lot of sending! Please wait a bit." }

  def index
    @gifts = @event.gifts.includes(:guest, thank_you: { media_attachment: :blob }).order(:created_at)
    @extra = @event.thank_yous.where(gift_id: nil).includes(media_attachment: :blob).order(:created_at)
    @guests = @event.guests.order(:name)
  end

  def new
    gift = @event.gifts.find_by(id: params[:gift_id])
    return redirect_to(edit_event_thank_you_path(@event, gift.thank_you)) if gift&.thank_you

    guest = gift&.guest || @event.guests.find_by(id: params[:guest_id])
    @thank_you = @event.thank_yous.new(gift: gift, guest: guest, recipient_name: gift&.giver_name || guest&.name)
  end

  def create
    @thank_you = @event.thank_yous.new(thank_you_params)
    @thank_you.gift = @event.gifts.find_by(id: params.dig(:thank_you, :gift_id))
    @thank_you.guest = @thank_you.gift&.guest || @event.guests.find_by(id: params.dig(:thank_you, :guest_id))
    if @thank_you.save
      redirect_to event_thank_yous_path(@event), notice: "Thank-you for #{@thank_you.recipient_name} saved."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @thank_you.media = nil if params[:remove_media] == "1"
    if @thank_you.update(thank_you_params)
      redirect_to event_thank_yous_path(@event), notice: "Thank-you for #{@thank_you.recipient_name} saved."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @thank_you.destroy!
    redirect_to event_thank_yous_path(@event), notice: "Thank-you removed.", status: :see_other
  end

  def deliver
    authorize! :send_messages
    channel = params[:channel].presence_in(ThankYouSender::CHANNELS) || ThankYouSender.channel_for(@thank_you)
    sent = ThankYouSender.new(@thank_you, channel: channel).deliver!
    redirect_to event_thank_yous_path(@event), notice: sent ? "Sent to #{@thank_you.recipient_name}." : "That thank-you was already sent."
  rescue ThankYouSender::Unavailable => e
    redirect_to event_thank_yous_path(@event), alert: "#{e.message}."
  end

  # Sends every ready, unsent thank-you to everyone we can reach.
  def deliver_all
    authorize! :send_messages
    sent = skipped = 0
    @event.thank_yous.where(sent_at: nil).find_each do |thank_you|
      next skipped += 1 unless thank_you.ready? && (channel = ThankYouSender.channel_for(thank_you))

      ThankYouSender.new(thank_you, channel: channel).deliver! ? sent += 1 : skipped += 1
    rescue ThankYouSender::Unavailable
      skipped += 1
    end
    redirect_to event_thank_yous_path(@event),
      notice: "Sent #{helpers.pluralize(sent, 'thank-you')}.#{" #{skipped} not ready or with no way to reach them — share those from your phone." if skipped.positive?}"
  end

  # For thank-yous the host shared from their own phone.
  def mark_sent
    @thank_you.update!(sent_at: @thank_you.sent_at || Time.current, sent_via: @thank_you.sent_via || "shared")
    redirect_to event_thank_yous_path(@event), notice: "Marked as sent."
  end

  private
    def set_thank_you
      @thank_you = @event.thank_yous.find(params[:id])
    end

    def thank_you_params
      permitted = params.fetch(:thank_you, {}).permit(:recipient_name, :recipient_email, :recipient_phone, :message, :signed)
      # Three capture buttons (video camera, photo camera, library); whichever was used wins.
      media = params.values_at(:media_video, :media_photo, :media_library).find { |f| f.respond_to?(:content_type) }
      media ? permitted.merge(media: media) : permitted
    end
end
