class ThankYouMailer < ApplicationMailer
  def note
    @thank_you = params[:thank_you]
    @url = params[:url]
    @event = @thank_you.event
    @design = InvitationDesign.for(@event)
    from_name = @thank_you.signed.to_s.sub(/\A(love|thanks|xo+),?\s*/i, "").presence || @event.display_host_name
    mail(to: email_address_with_name(@thank_you.recipient_email, @thank_you.recipient_name),
      from: email_address_with_name(Mail::Address.new(ApplicationMailer.from_address).address, "#{from_name} via Cordially"),
      reply_to: @event.owner.email_address,
      subject: "A thank-you from #{from_name}")
  end
end
