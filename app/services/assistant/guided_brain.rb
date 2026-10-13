module Assistant
  # A step-by-step texting assistant that needs no AI provider: it walks a host through name →
  # email → what's the occasion → when → where → design → guests → SEND, plus STATUS, EDIT, NEW,
  # and thank-yous (text a photo or video, say who it's for, reply SEND). Used when
  # ANTHROPIC_API_KEY isn't set — in development, in tests, or as a fallback.
  class GuidedBrain
    PICKS = %w[confetti-burst balloon-bunch garden-arch deco-fan starlit festival-lights meadow seaside].freeze
    COMMANDS = "Text NEW for a new card, STATUS for replies, EDIT to fine-tune the design on the web, GUESTS to add people, SEND to send it, or a photo/video for a thank-you."

    def initialize(conversation, inbound)
      @conversation = conversation
      @inbound = inbound
      @actions = Actions.new(conversation, inbound: inbound)
    end

    def reply
      text = @inbound.body.to_s.strip
      command = text.upcase.gsub(/[^A-Z ]/, "").strip

      return start_thank_you if @inbound.media.any? && @conversation.user && @actions.event
      return COMMANDS if command.in?(%w[HELP MENU COMMANDS])
      return account_step(text) unless @conversation.user

      case command
      when "NEW", "NEW CARD", "START" then step!("ask_title", "What are we celebrating? (e.g. \"Jonah's 5th birthday\")")
      when "STATUS" then @actions.status
      when "EDIT", "DESIGN" then "Fine-tune it here: #{@actions.web_link(page: 'design')}"
      when "GUESTS" then step!("ask_guests", guests_prompt)
      when "SEND", "SEND IT", "YES"
        @conversation.stage == "thanks_send" ? send_thank_you : send_cards
      else stage_step(text)
      end
    rescue Error => e
      e.message
    end

    private
      attr_reader :actions

      def step!(stage, reply)
        @conversation.update!(stage: stage)
        reply
      end

      def account_step(text)
        case @conversation.stage
        when "ask_name"
          @conversation.store!(name: text.squish.first(80))
          step!("ask_email", "Nice to meet you, #{text.split.first}! What's your email? It's for your account and reply notifications.")
        when "ask_email"
          result = actions.create_account(name: @conversation.data_value(:name), email: text)
          return step!("waiting_link", result) unless @conversation.reload.user

          step!("ask_title", "You're all set. What are we celebrating? (e.g. \"Jonah's 5th birthday\")")
        when "waiting_link"
          "Tap the link I emailed to connect this phone, then text me again."
        else
          step!("ask_name", "Hi! I'm Cordially — I make beautiful invitations by text. What's your name?")
        end
      end

      def stage_step(text)
        case @conversation.stage
        when "ask_title"
          actions.create_event(title: text.squish.first(120), track_kids: text.match?(/birthday|kid|baby|shower|\b\d{1,2}(st|nd|rd|th)\b/i))
          step!("ask_when", "Lovely. When is it? (e.g. Sat Nov 14 2pm)")
        when "ask_when"
          time = DateText.parse(text, zone: actions.event.zone)
          return "Sorry, I couldn't read that date. Try like \"Nov 14 2pm\"." unless time

          actions.update_event(starts_at: time.strftime("%Y-%m-%dT%H:%M"))
          step!("ask_where", "Got it: #{time.strftime('%a %b %-d at %-l:%M %p')}. Where is it? (or SKIP)")
        when "ask_where"
          actions.update_event(location_name: text.squish.first(120)) unless text.match?(/\Askip\z/i)
          step!("ask_design", design_menu)
        when "ask_design"
          key = PICKS[text.to_i - 1] if text.match?(/\A\d+\z/)
          return design_menu unless key

          actions.set_design(template: key)
          step!("ask_guests", "#{InvitationTemplate.find(key).name} it is! See it or fine-tune: #{actions.web_link(page: 'design')}\n#{guests_prompt}")
        when "ask_guests"
          people = GuestText.parse(text)
          return guests_prompt if people.empty?

          result = actions.add_guests(guests: people)
          step!("ready", "#{result} Send more, or reply SEND to send the invitations.")
        when "thanks_who"
          save_thank_you(text)
        else
          "#{actions.event ? actions.summary : 'No card yet.'}\n#{COMMANDS}"
        end
      end

      def design_menu
        "Pick a look (reply a number):\n" + PICKS.each_with_index.map { |key, i| "#{i + 1} #{InvitationTemplate.find(key).name}" }.join("\n")
      end

      def guests_prompt
        "Who's invited? One per line: name and mobile or email.\nDana Whitfield 555-0100\nLee Park lee@example.com"
      end

      def send_cards
        result = actions.send_invitations!
        step!("sent", "#{result} I'll text you as replies come in. Text STATUS any time.")
      end

      def start_thank_you
        @conversation.store!(thank_you_media_message_id: @inbound.id)
        step!("thanks_who", "Ooh, a thank-you! Who's it for? (and the gift, if you like: \"Dana — Lego set\")")
      end

      def save_thank_you(text)
        recipient, gift = text.split(/\s+[—-]\s+|,/, 2).map(&:strip)
        media_message = @conversation.messages.find_by(id: @conversation.data_value(:thank_you_media_message_id))
        result = Actions.new(@conversation, inbound: media_message || @inbound).save_thank_you(recipient: recipient, gift: gift)
        @conversation.store!(thank_you_recipient: recipient)
        step!("thanks_send", "#{result} Reply SEND to send it.")
      end

      def send_thank_you
        result = actions.send_thank_you!(recipient: @conversation.data_value(:thank_you_recipient))
        step!("ready", result)
      end
  end
end
