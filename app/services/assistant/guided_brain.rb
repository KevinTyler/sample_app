module Assistant
  # A step-by-step agent that needs no AI provider: it walks a host through name → email → what's
  # the occasion → when → where → design → guests → SEND, plus STATUS, EDIT, NEW, thank-yous (send a
  # photo or video, say who it's for, reply SEND), guest-list files (send a spreadsheet or contacts
  # file, reply RECREATE / ADD / CONTACTS), and YES/NO to things the agent proposed. Used when
  # ANTHROPIC_API_KEY isn't set — in development, in tests, or as a fallback.
  class GuidedBrain
    PICKS = %w[confetti-burst balloon-bunch garden-arch deco-fan starlit festival-lights meadow seaside].freeze
    COMMANDS = "Say NEW for a new card, STATUS for replies, EDIT to fine-tune the design, GUESTS to add people, SEND to send it, " \
               "TODO for anything that needs you, or send a guest-list spreadsheet, a contacts file, or a photo/video for a thank-you."
    NEGATIVE = /\A\s*(no|nope|nah|not now|later|skip|don'?t|dismiss)\b/i
    INTENTS = {
      /\b(paperless|import|bring (over|my|in)|switch(ing)?|spreadsheet|address book|contacts? file)\b/i => :import_help,
      /\b(plan|new (card|event|invitation)|make (a|an|another) (card|invitation)|something new)\b/i => :new,
      /\b(who.*(replied|coming)|status|replies|headcount)\b/i => :status,
      /\b(needs? me|to ?do|anything (for|to do))\b/i => :proposals,
      /\bthank/i => :thanks_help
    }.freeze

    def initialize(conversation, inbound)
      @conversation = conversation
      @inbound = inbound
      @actions = Actions.new(conversation, inbound: inbound)
    end

    def cards = @actions.cards

    def reply
      text = @inbound.body.to_s.strip
      command = text.upcase.gsub(/[^A-Z ]/, "").strip

      return read_file if @inbound.import_files.any? && @conversation.user
      return start_thank_you if @inbound.photos_and_videos.any? && @conversation.user && @actions.event
      return COMMANDS if command.in?(%w[HELP MENU COMMANDS])
      return account_step(text) unless @conversation.user
      return answer_proposal(@proposal, text) if (@proposal = proposal_in_question) && (text.match?(Actions::AFFIRMATIVE) || text.match?(NEGATIVE))

      case command
      when "RECREATE", "RECREATE IT" then apply_import("new_event")
      when "ADD", "ADD THEM" then apply_import("current_event")
      when "CONTACTS", "IMPORT", "SAVE", "JUST CONTACTS" then apply_import("contacts")
      when "TODO", "TO DO" then actions.list_proposals
      when "SETTINGS" then "Your usual settings: #{actions.preferences_summary} Change them under Settings, or on the Switching page if you're coming from Paperless Post."
      when "CONNECT", "TEXT ME" then actions.connect_phone
      when "NEW", "NEW CARD", "START" then step!("ask_title", "What are we celebrating? (e.g. \"Jonah's 5th birthday\")")
      when "STATUS" then @actions.status
      when "EDIT", "DESIGN" then "Fine-tune it here: #{@actions.web_link(page: 'design')}"
      when "GUESTS" then step!("ask_guests", guests_prompt)
      when "SEND", "SEND IT", "YES"
        @conversation.stage == "thanks_send" ? send_thank_you : send_cards
      else intent_step(text) || stage_step(text)
      end
    rescue Error => e
      e.message
    end

    private
      attr_reader :actions

      # Plain-language requests when we're not in the middle of a step.
      def intent_step(text)
        return unless @conversation.stage.in?([ nil, "ready", "sent" ])

        case INTENTS.find { |pattern, _| text.match?(pattern) }&.last
        when :new then step!("ask_title", "What are we celebrating? (e.g. \"Jonah's 5th birthday\")")
        when :import_help
          "Send me the file and I'll bring everyone over — a Paperless Post guest-list export (Excel or CSV), a contacts file from your phone, Google or Outlook, " \
            "or just paste a list. You'll see what's in it before anything is saved, and replies people already gave come along."
        when :status then actions.event ? actions.status : actions.list_events
        when :proposals then actions.list_proposals
        when :thanks_help then "After the party: send me a photo or video (a kid holding their gift is perfect) and tell me who it's for. I'll make it a thank-you and send it when you say SEND."
        end
      end

      def read_file
        result = actions.read_guest_list
        import = @conversation.user.contact_imports.pending.order(:created_at).last
        @conversation.store!(import_id: import&.id)
        options = [ ("RECREATE to set up “#{import.suggested_title}” with these guests#{' and their replies' if import&.people&.has_replies?}" if import),
                    ("ADD to put them on #{actions.event.title}" if actions.event&.draft? || actions.event&.published?),
                    "CONTACTS to just save them to your contacts" ].compact
        step!("ready", "#{result.sub(/\AImport \d+ is ready to review \(nothing saved yet\)\. /, '')}\nReply #{options.to_sentence(two_words_connector: ' or ', last_word_connector: ', or ')}.")
      end

      def apply_import(mode)
        import_id = @conversation.data_value(:import_id) || @conversation.user.contact_imports.pending.order(:created_at).last&.id
        return "Send me a guest-list spreadsheet or contacts file first." unless import_id

        result = actions.apply_guest_list(import_id: import_id, mode: mode)
        @conversation.store!(import_id: nil)
        follow_up = mode == "new_event" ? " When is it, and where? (e.g. Sat Nov 14 2pm)" : ""
        step!(mode == "new_event" ? "ask_when" : "ready", "#{result}#{follow_up}")
      end

      # The proposal the agent most recently brought up on this thread, if it's still open.
      def proposal_in_question
        last_out = @conversation.messages.where(direction: "out").reorder(created_at: :desc, id: :desc).first
        id = last_out&.cards&.find { |card| card["type"] == "proposal" }&.dig("proposal_id")
        id && @conversation.user.agent_proposals.pending.find_by(id: id)
      end

      def answer_proposal(proposal, text)
        text.match?(NEGATIVE) ? actions.dismiss_proposal(proposal_id: proposal.id) : actions.approve_proposal(proposal_id: proposal.id)
      end

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
