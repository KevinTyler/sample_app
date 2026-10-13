module Assistant
  # The Cordially agent's natural-language brain, powered by Claude through the Anthropic SDK's tool
  # runner. Each host message (a text, or a message on the web) is one turn: recent thread history
  # (plain text) + a context note about the host's account, events, imports and anything waiting on
  # them, then Claude works the tools until it has a reply. The thread is the memory: nothing but the
  # plain-text conversation is replayed next turn; everything else lives in the database.
  class ClaudeBrain
    MODEL = :"claude-opus-5-5"
    MAX_TOOL_ROUNDS = 10
    REFUSAL_REPLY = "Sorry, I can't help with that one. I'm here for your invitations, guests and thank-yous.".freeze

    attr_reader :actions

    delegate :cards, to: :actions

    def self.available?
      ENV["ANTHROPIC_API_KEY"].present? || ENV["ANTHROPIC_AUTH_TOKEN"].present?
    end

    def initialize(conversation, inbound, client: nil)
      @conversation = conversation
      @inbound = inbound
      @client = client || Anthropic::Client.new
    end

    def reply
      @actions = Actions.new(@conversation, inbound: @inbound)
      runner = @client.beta.messages.tool_runner(
        model: MODEL,
        max_tokens: 16_000,
        max_iterations: MAX_TOOL_ROUNDS,
        system_: [ { type: "text", text: Prompt.system, cache_control: { type: "ephemeral" } } ],
        tools: Tools.build(actions),
        messages: transcript(actions),
        output_config: { effort: "medium" },
        # If a safety classifier declines the request, retry on a fallback model chosen by the API.
        betas: [ "server-side-fallback-2026-07-01" ],
        fallbacks: :default
      )
      last = nil
      runner.each_message { |message| last = message }
      return REFUSAL_REPLY if last.nil? || last.stop_reason == :refusal

      text = last.content.select { |block| block.type == :text }.map(&:text).join("\n").strip
      text.presence || "Done."
    end

    private
      # Recent thread as alternating user/assistant text; the newest host text carries the context note.
      def transcript(actions)
        turns = []
        @conversation.recent_messages.each do |message|
          role = message.inbound? ? :user : :assistant
          text = message.body.to_s
          if message.inbound?
            files = message.import_files.map { |f| f["filename"].presence || "a contacts/spreadsheet file" }
            text += " [attached #{files.join(', ')} — a guest list or contacts file]" if files.any?
            text += " [attached #{message.photos_and_videos.size} photo/video]" if message.photos_and_videos.any?
          end
          next if text.strip.empty?

          if turns.last && turns.last[:role] == role
            turns.last[:content] += "\n#{text}"
          else
            turns << { role: role, content: text }
          end
        end
        turns.shift while turns.first && turns.first[:role] != :user
        turns << { role: :user, content: "(no text)" } if turns.empty? || turns.last[:role] != :user

        latest = turns.pop
        turns << { role: :user, content: [ { type: "text", text: context_note(actions) }, { type: "text", text: latest[:content] } ] }
        turns
      end

      def context_note(actions)
        user = @conversation.user
        zone = @conversation.data_value(:time_zone).presence || user&.time_zone.presence || "America/New_York"
        lines = [ "Context from Cordially (not written by the host):",
                  "Today is #{Time.current.in_time_zone(zone).strftime('%A, %B %-d, %Y')}.",
                  "Channel: #{channel_description}" ]
        if user
          lines << "Account: #{user.name} <#{user.email_address}>.#{" Switched from #{user.switched_from.humanize}." if user.switched_from}"
          lines << "Usual settings: #{actions.preferences_summary}"
          lines << (actions.event ? "Current event: #{actions.summary}" : "No current event.")
          upcoming = user.accessible_events.where.not(status: "cancelled").where("starts_at IS NULL OR starts_at > ?", 1.day.ago).order(:starts_at).limit(6)
          lines << "Their events: #{upcoming.map { |e| "#{e.id} #{e.title} (#{e.status})" }.join('; ')}." if upcoming.any?
          lines << "Contacts: #{user.contacts.count}."
          imports = user.contact_imports.pending.order(created_at: :desc).limit(2)
          imports.each { |i| lines << "Import #{i.id} waiting for the host's decision: #{i.description}" }
          waiting = user.agent_proposals.pending.recent_first.limit(5)
          lines << "Waiting on the host: #{waiting.map { |p| "proposal #{p.id}: #{p.pitch}" }.join(' | ')}" if waiting.any?
        elsif @conversation.data_value(:pending_email)
          lines << "Not connected yet: waiting for them to tap the link emailed to #{@conversation.data_value(:pending_email)}."
        else
          lines << "No account yet."
        end
        lines.join("\n")
      end

      def channel_description
        case @conversation.channel
        when "web" then "web chat in the Cordially app (it shows cards with buttons for events, imports and proposals under your reply; links are clickable)."
        when "whatsapp" then "WhatsApp from #{@conversation.address}."
        else "SMS from #{@conversation.address}."
        end
      end
  end
end
