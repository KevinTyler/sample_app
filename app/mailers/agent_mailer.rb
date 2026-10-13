# The agent reaching a host by email when something needs them (for hosts who chose email, or
# whose phone thread can't be texted right now). Approving happens in Cordially, one tap.
class AgentMailer < ApplicationMailer
  def needs_you
    @user = params[:user]
    @proposals = @user.agent_proposals.pending.where(id: params[:proposal_ids]).includes(:event).to_a
    return if @proposals.empty?

    @url = agent_url(**Messaging.url_options)
    subject = @proposals.one? ? @proposals.first.title : "#{@proposals.size} things need you on Cordially"
    mail(to: @user.email_address, subject: subject)
  end
end
