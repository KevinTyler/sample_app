module Assistant
  # Natural-language texting assistant, powered by Claude through the Anthropic SDK's tool runner.
  # Each inbound text is one turn: recent thread history (plain text) + a context note about the
  # host's account and current event, then Claude works the tools until it has a reply to text back.
  # The thread itself is the memory: nothing but the plain-text conversation is replayed next turn.
  class ClaudeBrain
    MODEL = :"claude-opus-5-5"
    MAX_TOOL_ROUNDS = 10
    REFUSAL_REPLY = "Sorry, I can't help with that one. I'm here for your invitations, guests and thank-yous.".freeze

    def self.available?
      ENV["ANTHROPIC_API_KEY"].present? || ENV["ANTHROPIC_AUTH_TOKEN"].present?
    end

    def initialize(conversation, inbound, client: nil)
      @conversation = conversation
      @inbound = inbound
      @client = client || Anthropic::Client.new
    end

    def reply
      actions = Actions.new(@conversation, inbound: @inbound)
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
          text += " [attached #{message.media.size} photo/video]" if message.inbound? && message.media.any?
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
        lines = [ "Context from Cordially (not written by the host):",
                  "Today is #{Time.current.in_time_zone(@conversation.data_value(:time_zone).presence || 'America/New_York').strftime('%A, %B %-d, %Y')}.",
                  "Channel: #{@conversation.channel == 'whatsapp' ? 'WhatsApp' : 'SMS'} from #{@conversation.address}." ]
        if user
          lines << "Account: #{user.name} <#{user.email_address}>."
          lines << (actions.event ? "Current event: #{actions.summary}" : "No current event.")
        elsif @conversation.data_value(:pending_email)
          lines << "Not connected yet: waiting for them to tap the link emailed to #{@conversation.data_value(:pending_email)}."
        else
          lines << "No account yet."
        end
        lines.join("\n")
      end
  end
end
