module AssistantHelper
  # The number hosts text to make a card (set ASSISTANT_PHONE_NUMBER / ASSISTANT_WHATSAPP_NUMBER).
  def assistant_sms_number = ENV["ASSISTANT_PHONE_NUMBER"].presence
  def assistant_whatsapp_number = ENV["ASSISTANT_WHATSAPP_NUMBER"].presence

  def assistant_available?
    assistant_sms_number || assistant_whatsapp_number || Messaging.outbox_enabled?
  end

  def assistant_links(prefill = "Hi! I'd like to make an invitation.")
    links = []
    links << [ "Text #{assistant_sms_number}", "sms:#{assistant_sms_number}?&body=#{ERB::Util.url_encode(prefill)}" ] if assistant_sms_number
    links << [ "WhatsApp", "https://wa.me/#{assistant_whatsapp_number.delete('^0-9')}?#{ { text: prefill }.to_query }" ] if assistant_whatsapp_number
    links << [ "Try it here (dev simulator)", dev_assistant_path ] if links.empty? && Messaging.outbox_enabled?
    links
  end
end
