# Tells hosts about guest replies: right away (one email per reply) or in a daily summary,
# per each host's preference. Door staff aren't notified, and nobody is told about a reply
# they recorded themselves.
class HostNotifier
  REPLY_ACTIONS = %w[rsvp_submitted rsvp_changed].freeze

  def self.reply_recorded(activity)
    return unless activity.action.in?(REPLY_ACTIONS)

    recipients(activity.event).each do |user|
      next if user.id == activity.user_id || user.rsvp_notifications != "instant"

      HostMailer.with(user: user, activity: activity).reply_received.deliver_later
    end
  end

  # Owner plus co-hosts with guest-list access.
  def self.recipients(event)
    [ event.owner, *event.memberships.includes(:user).select { |m| m.role == "editor" }.map(&:user) ].uniq
  end

  # Sends each "daily" host one summary of replies since their last one. Safe to run often:
  # a host gets at most one summary per 20 hours.
  def self.send_digests(now: Time.current)
    User.where(rsvp_notifications: "daily").where("last_digest_at IS NULL OR last_digest_at < ?", now - 20.hours).find_each do |user|
      since = user.last_digest_at || now - 1.day
      activities = Activity.where(event_id: user.accessible_events.select(:id), action: REPLY_ACTIONS, created_at: since..now)
        .where("activities.user_id IS NULL OR activities.user_id <> ?", user.id)
      user.update_columns(last_digest_at: now)
      HostMailer.with(user: user, activity_ids: activities.ids).daily_digest.deliver_later if activities.any?
    end
  end
end
