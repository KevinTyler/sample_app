class CohostMailer < ApplicationMailer
  def invite
    @invitation = params[:invitation]
    @event = @invitation.event
    @url = cohost_acceptance_url(params[:token], **Messaging.url_options)
    inviter = @invitation.invited_by&.name || "The host"
    mail(to: @invitation.email, subject: "#{inviter} invited you to co-host #{@event.title}",
      reply_to: @invitation.invited_by&.email_address)
  end
end
