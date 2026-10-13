# Something the agent noticed and wants the host's go-ahead on: nudging people who haven't replied,
# a last call after the deadline, sending a draft that hasn't gone out, a day-before reminder,
# texting guests whose invitation email bounced, starting thank-yous. Proposals never act on their
# own — the host approves with a button on the web or by replying YES to the agent's text, and the
# action then runs as the host, through the same messages and permissions as the web app.
class AgentProposal < ApplicationRecord
  KINDS = %w[nudge_pending last_call send_draft day_before text_instead fix_contacts thank_yous].freeze
  STATUSES = %w[pending done dismissed expired failed].freeze

  belongs_to :user
  belongs_to :event, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :title, presence: true

  scope :pending, -> { where(status: "pending").where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def pending? = status == "pending" && (expires_at.nil? || expires_at.future?)
  def actionable? = action_label.present?

  # What the agent says when it brings this up by text (the web shows it as a card).
  def pitch
    [ title_sentence, body ].compact_blank.join(" ")
  end

  def title_sentence
    title.to_s.match?(/[.!?]\z/) ? title : "#{title}."
  end

  # Runs the proposed action as `by` (the host). Returns a short result for the agent to report.
  def approve!(by: user)
    claimed = self.class.where(id: id, status: "pending").update_all(status: "done", decided_at: Time.current, updated_at: Time.current)
    raise Assistant::Error, "That's already been taken care of." unless claimed == 1

    reload
    outcome = perform(by)
    update!(result: outcome)
    Activity.record(event: event, user: by, action: "agent_proposal_approved", data: { kind: kind }) if event
    outcome
  rescue Assistant::Error, ActiveRecord::RecordInvalid => e
    update_columns(status: "failed", result: e.message.truncate(250), updated_at: Time.current) if persisted? && status == "done" && result.nil?
    raise Assistant::Error, e.message
  end

  def dismiss!
    self.class.where(id: id, status: "pending").update_all(status: "dismissed", decided_at: Time.current, updated_at: Time.current)
    reload
  end

  private
    def perform(by)
      return payload["done_message"].presence || "Done." unless actionable?

      policy = EventPolicy.new(by, event)
      raise Assistant::Error, "You don't have permission to message guests for #{event.title}." unless event && policy.can?(:send_messages)
      raise Assistant::Error, "#{event.title} has been cancelled." if event.cancelled?

      case kind
      when "nudge_pending" then nudge(by)
      when "last_call" then last_call(by)
      when "send_draft" then send_draft(by)
      when "day_before" then day_before(by)
      when "text_instead" then text_instead(by)
      when "thank_yous" then payload["done_message"].presence || "Open Thank-yous to start."
      end
    end

    def nudge(by)
      guests = event.guests.where(rsvp_status: "pending", unsubscribed_at: nil)
      count = send_to!(guests, by: by, subject: "Can you make it? #{event.title}",
        body: "We'd love to know if you can make it#{deadline_phrase}. Tap your invitation link to reply — it only takes a moment.")
      "Sent a friendly nudge to #{count} #{'guest'.pluralize(count)} who hadn't replied."
    end

    def last_call(by)
      if event.rsvp_deadline && event.rsvp_deadline.past?
        extended = [ 2.days.from_now, event.starts_at && event.starts_at - 1.hour ].compact.min
        event.update!(rsvp_deadline: extended) if extended.future?
      end
      guests = event.guests.where(rsvp_status: "pending", unsubscribed_at: nil)
      count = send_to!(guests, by: by, subject: "Last call: #{event.title}",
        body: "Replies are closing soon#{deadline_phrase}. If you can still let us know whether you're coming, tap your invitation link.")
      "Replies are open until #{event.local(event.rsvp_deadline).strftime('%a %b %-d')} and a last call went to #{count} #{'guest'.pluralize(count)}."
    end

    def send_draft(by)
      raise Assistant::Error, "#{event.title} has no guests yet." if event.guests.none?

      unless event.published?
        raise Assistant::Error, "Before it can go out: #{event.errors.full_messages.to_sentence}" unless event.publish

        Activity.record(event: event, user: by, action: "event_published")
      end
      guests = event.guests.where(unsubscribed_at: nil).where.not(id: Delivery.where(message_id: event.messages.select(:id)).select(:guest_id))
      count = send_to!(guests, by: by, kind: event.card_type)
      "#{event.title} is on its way to #{count} #{'guest'.pluralize(count)}."
    end

    def day_before(by)
      guests = event.guests.where(rsvp_status: %w[yes maybe], unsubscribed_at: nil)
      count = send_to!(guests, by: by, subject: "See you tomorrow: #{event.title}",
        body: "Just a reminder that #{event.title} is tomorrow. Your invitation has the time, place and everything else you need.")
      "Reminded #{count} #{'guest'.pluralize(count)} who are coming."
    end

    def text_instead(by)
      raise Assistant::Error, "Texting isn't set up yet." unless Messaging.sms_enabled?

      guests = event.guests.where(id: Array(payload["guest_ids"])).where.not(phone: nil).where(unsubscribed_at: nil)
      count = send_to!(guests, by: by, kind: event.card_type, channels: %w[sms])
      "Texted the #{event.card_type_name.downcase} to #{count} #{'guest'.pluralize(count)} instead."
    end

    # Email to guests with an address; a text to those with only a mobile (when texting is set up).
    def send_to!(guests, by:, kind: "reminder", subject: nil, body: nil, channels: nil)
      ids = guests.ids
      return 0 if ids.empty?

      groups = if channels
        { channels.first => ids }
      else
        texting = Messaging.sms_enabled? ? event.guests.where(id: ids, email: nil).where.not(phone: nil).ids : []
        { "email" => ids - texting, "sms" => texting }
      end
      groups.sum do |channel, group_ids|
        next 0 if group_ids.empty?

        message = event.messages.idempotent_create!(idempotency_key: "proposal-#{id}-#{channel}", kind: kind, author: by,
          channels: [ channel ], subject: subject, body: body, audience: { "guest_ids" => group_ids, "resend" => kind == "reminder" })
        message.dispatch! unless message.status == "dispatched"
        message.recipients_count.to_i
      end
    end

    def deadline_phrase
      return "" unless event.rsvp_deadline

      " — replies close #{event.local(event.rsvp_deadline).strftime('%A, %B %-d')}"
    end
end
