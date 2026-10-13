# Emails to hosts about their events: each reply as it arrives, or a daily summary.
class HostMailer < ApplicationMailer
  helper :events, :rsvp

  def reply_received
    @user = params[:user]
    @activity = params[:activity]
    @event = @activity.event
    @guest = @activity.guest
    return unless @guest && @user.accessible_events.exists?(@event.id)

    @url = event_guests_url(@event, **Messaging.url_options)
    mail(to: @user.email_address, subject: "#{reply_headline(@activity)} · #{@event.title}")
  end

  def daily_digest
    @user = params[:user]
    @activities = Activity.where(id: params[:activity_ids]).includes(:event, :guest).order(:created_at)
      .select { |a| @user.accessible_events.exists?(a.event_id) }
    return if @activities.empty?

    @by_event = @activities.group_by(&:event)
    mail(to: @user.email_address, subject: "#{@activities.size} new #{'reply'.pluralize(@activities.size)} on Cordially")
  end

  private
    def reply_headline(activity)
      view_context.activity_sentence(activity)
    end
end
