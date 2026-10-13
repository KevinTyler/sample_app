module ThankYousHelper
  # Opens the host's own messaging app with the thank-you ready to send (from their number).
  def thank_you_share_links(thank_you)
    url = thank_you_page_url(thank_you.token)
    text = thank_you.share_text(url)
    links = []
    links << [ "Text", "sms:#{thank_you.recipient_phone}?&body=#{ERB::Util.url_encode(text)}" ]
    digits = thank_you.recipient_phone.to_s.delete("^0-9")
    links << [ "WhatsApp", "https://wa.me/#{digits}?#{ { text: text }.to_query }" ]
    links
  end

  def guest_heart_path_for(thank_you)
    thank_you_page_heart_path(thank_you.token)
  end

  def thank_you_status(thank_you)
    if thank_you.nil? || !thank_you.ready? then [ "Needs a thank-you", "warning" ]
    elsif thank_you.hearted_at then [ "Loved it", "seen" ]
    elsif thank_you.viewed_at then [ "Opened", "rsvp-yes" ]
    elsif thank_you.sent? then [ "Sent", "sent" ]
    else [ thank_you.media.attached? ? "Recorded · not sent" : "Written · not sent", "queued" ]
    end
  end
end
