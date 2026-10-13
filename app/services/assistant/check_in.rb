module Assistant
  # The agent's rounds: looks over a host's events and raises a proposal for anything that needs
  # them — at most once per situation (each has a stable dedupe key) — then tells the host the way
  # they asked to be reached: a text on their connected phone, an email, or only in Cordially.
  # Proposals expire when they stop making sense (the deadline passes, the party starts).
  class CheckIn
    NUDGE_WINDOW = 5.days
    DRAFT_WINDOW = 21.days

    def self.run_all(now: Time.current)
      AgentProposal.where(status: "pending").where(expires_at: ..now).update_all(status: "expired", updated_at: now)
      User.where(id: Event.where.not(status: "cancelled").where("starts_at IS NULL OR starts_at > ?", now - 8.days).select(:owner_id)).find_each do |user|
        new(user, now: now).run
      rescue StandardError => e
        Rails.logger.error("[agent] check-in failed for user #{user.id}: #{e.class}: #{e.message}")
      end
    end

    def initialize(user, now: Time.current)
      @user = user
      @now = now
    end

    # Returns the proposals raised this time.
    def run
      raised = @user.owned_events.where.not(status: "cancelled").flat_map { |event| candidates(event) }.filter_map { |attrs| raise!(attrs) }
      notify(raised) if raised.any?
      raised
    end

    private
      def candidates(event)
        [ nudge_pending(event), last_call(event), send_draft(event), day_before(event), bounced(event), thank_yous(event) ].compact
      end

      def raise!(attrs)
        @user.agent_proposals.create!(attrs)
      rescue ActiveRecord::RecordNotUnique
        nil # already raised for this situation
      end

      # Guests the card reached who haven't answered (the same people a reminder goes to).
      def pending_guests(event)
        event.guests.where(rsvp_status: "pending", unsubscribed_at: nil).where.not(invited_at: nil)
      end

      def local_day(event, time)
        event.local(time).strftime("%A")
      end

      # --- Situations -------------------------------------------------------

      def nudge_pending(event)
        return unless event.published? && event.collects_replies? && !event.auto_nudge?
        return unless (closes = event.rsvp_closes_at) && closes.between?(@now + 12.hours, @now + NUDGE_WINDOW)
        return if event.messages.where(kind: "reminder").where(dispatched_at: (@now - 3.days)..).exists?

        count = pending_guests(event).count
        return if count.zero?

        { event: event, kind: "nudge_pending", dedupe_key: "nudge:#{event.id}:#{closes.to_date}", expires_at: closes,
          title: "#{count} #{count == 1 ? 'guest hasn’t' : 'guests haven’t'} replied to #{event.title}",
          body: "#{event.rsvp_deadline ? 'Replies close' : 'It’s'} #{local_day(event, closes)}. Want me to send them a friendly nudge?",
          action_label: "Send the nudge", payload: { "count" => count } }
      end

      def last_call(event)
        return unless event.published? && event.collects_replies? && event.rsvp_deadline && event.starts_at
        return unless event.rsvp_deadline.between?(@now - 2.days, @now) && event.starts_at > @now + 1.day

        count = pending_guests(event).count
        return if count.zero?

        { event: event, kind: "last_call", dedupe_key: "last_call:#{event.id}:#{event.rsvp_deadline.to_date}", expires_at: event.starts_at - 1.day,
          title: "Replies for #{event.title} closed with #{count} still to hear from",
          body: "Shall I reopen replies for two days and send them a last call?",
          action_label: "Send a last call", payload: { "count" => count } }
      end

      def send_draft(event)
        return unless event.draft? && event.starts_at&.between?(@now, @now + DRAFT_WINDOW) && event.created_at < @now - 1.day

        count = event.guests.count
        return if count.zero?

        days = ((event.starts_at - @now) / 1.day).floor
        { event: event, kind: "send_draft", dedupe_key: "send_draft:#{event.id}:#{event.starts_at.to_date}", expires_at: event.starts_at,
          title: "#{event.title} is #{days <= 1 ? 'almost here' : "in #{days} days"} and hasn’t gone out",
          body: "Want me to send it to your #{count} #{'guest'.pluralize(count)} now?",
          action_label: "Send it now", payload: { "count" => count } }
      end

      def day_before(event)
        return unless event.published? && !event.auto_day_before? && event.starts_at&.between?(@now + 18.hours, @now + 44.hours)
        return if event.messages.where(kind: "reminder").where(dispatched_at: (@now - 2.days)..).exists?

        count = event.guests.where(rsvp_status: %w[yes maybe], unsubscribed_at: nil).count
        return if count.zero?

        { event: event, kind: "day_before", dedupe_key: "day_before:#{event.id}:#{event.starts_at.to_date}", expires_at: event.starts_at - 2.hours,
          title: "#{event.title} is tomorrow",
          body: "Want me to send the #{count} #{count == 1 ? 'person' : 'people'} coming a reminder with the time and place?",
          action_label: "Send the reminder", payload: { "count" => count } }
      end

      def bounced(event)
        return unless event.published? && (event.starts_at.nil? || event.starts_at > @now)

        failed = Delivery.where(message_id: event.messages.where(kind: Message::CARD_KINDS).select(:id), channel: "email", status: %w[bounced failed])
          .where(updated_at: (@now - 7.days)..)
        guests = event.guests.where(id: failed.select(:guest_id), rsvp_status: "pending").to_a
        return if guests.empty?

        textable = Messaging.sms_enabled? ? guests.select(&:phone) : []
        names = guests.first(3).map(&:name).to_sentence
        if textable.any?
          { event: event, kind: "text_instead", dedupe_key: "text_instead:#{event.id}:#{guests.map(&:id).sort.join('-')}",
            expires_at: event.rsvp_closes_at,
            title: "#{guests.size} #{guests.size == 1 ? 'invitation' : 'invitations'} to #{event.title} bounced (#{names})",
            body: "#{textable.size == guests.size ? 'They all' : "#{textable.size} of them"} have a mobile number. Text the invitation instead?",
            action_label: "Text them", payload: { "guest_ids" => textable.map(&:id) } }
        else
          { event: event, kind: "fix_contacts", dedupe_key: "fix_contacts:#{event.id}:#{guests.map(&:id).sort.join('-')}",
            expires_at: event.rsvp_closes_at,
            title: "#{guests.size} #{guests.size == 1 ? 'invitation' : 'invitations'} to #{event.title} didn’t arrive (#{names})",
            body: "The email #{guests.size == 1 ? 'address looks' : 'addresses look'} wrong. Tell me a better email or mobile number and I'll resend.",
            payload: { "guest_ids" => guests.map(&:id), "done_message" => "Okay — I'll leave those for now." } }
        end
      end

      def thank_yous(event)
        ended = event.ends_at || (event.starts_at && event.starts_at + 3.hours)
        return unless event.published? && ended&.between?(@now - 7.days, @now - 12.hours) && event.thank_yous.none?

        coming = event.guests.where(rsvp_status: "yes").count
        return if coming.zero?

        { event: event, kind: "thank_yous", dedupe_key: "thank_yous:#{event.id}", expires_at: ended + 21.days,
          title: "Hope #{event.title} was wonderful!",
          body: "Ready for thank-yous? Log gifts as you open them — kids can record a little video for each — and I'll send them by text or email.",
          action_label: "Start thank-yous", payload: { "path" => "thank_yous", "done_message" => "Open Thank-yous for #{event.title} to log gifts and record notes — or text me a photo or video and say who it's for." } }
      end

      # --- Telling the host --------------------------------------------------

      def notify(proposals)
        web = AssistantConversation.for_web(@user)
        proposals.each do |proposal|
          web.reply!("", cards: [ { "type" => "proposal", "proposal_id" => proposal.id } ]) # the card says it all
        end

        case @user.agent_reach
        when "text" then text(proposals) || email(proposals)
        when "email" then email(proposals)
        end
        AgentProposal.where(id: proposals.map(&:id)).update_all(notified_at: @now)
      end

      def text(proposals)
        thread = @user.texting_conversation
        return false unless thread&.can_message?

        first, *rest = proposals
        more = rest.any? ? " (#{rest.size} more #{'thing'.pluralize(rest.size)} on your Cordially page.)" : ""
        answer = first.actionable? ? " Reply YES, or NO to skip." : ""
        thread.reply!("#{first.pitch}#{answer}#{more}", cards: [ { "type" => "proposal", "proposal_id" => first.id } ])
        true
      end

      def email(proposals)
        AgentMailer.with(user: @user, proposal_ids: proposals.map(&:id)).needs_you.deliver_later
        true
      end
  end
end
