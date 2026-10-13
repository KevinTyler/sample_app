# The Cordially agent: one set of actions (Assistant::Actions) and two brains (Claude, or a guided
# step-by-step fallback), reachable on the web ("Today") and by text (SMS or WhatsApp).
module Assistant
  module_function

  # Where hosts text the agent, for showing in the app (nil when texting isn't set up).
  def texting_number
    ENV["ASSISTANT_PHONE_NUMBER"].presence || ENV["ASSISTANT_WHATSAPP_NUMBER"].presence ||
      ("the phone simulator at /dev/assistant" if Messaging.outbox_enabled?)
  end

  def brain_for(conversation, message)
    ClaudeBrain.available? ? ClaudeBrain.new(conversation, message) : GuidedBrain.new(conversation, message)
  end
end
