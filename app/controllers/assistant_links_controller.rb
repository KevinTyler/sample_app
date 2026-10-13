# Connects a phone that texted the assistant to an existing account, after the account's owner
# taps the link we emailed them (so knowing someone's email isn't enough to take over their account).
class AssistantLinksController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 20, within: 10.minutes, by: -> { request.remote_ip }, with: -> { head :too_many_requests }

  def show
    @claim = claim
    render :invalid, status: :not_found unless @claim
  end

  def create
    data = claim
    return render(:invalid, status: :not_found) unless data

    conversation = AssistantConversation.find(data["conversation_id"])
    user = User.find(data["user_id"])
    if conversation.user_id.nil?
      conversation.update!(user: user)
      conversation.reply!("Connected to your Cordially account, #{user.first_name}! What would you like to make? Text NEW for a new card.")
    end
    redirect_to (authenticated? ? events_path : new_session_path), notice: "Your phone is connected. Text the assistant any time."
  end

  private
    def claim
      Rails.application.message_verifier(:assistant_link).verified(params[:token])
    end
end
