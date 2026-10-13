# Shows a one-time code the host texts to the agent's number to connect their phone. The code is
# rendered in this response only — never stored in plain text or put in the conversation.
class PhoneLinksController < ApplicationController
  rate_limit to: 10, within: 1.hour, by: -> { Current.user.id }, with: -> { redirect_to agent_path, alert: "Too many codes — try again in a bit." }

  def create
    @code = Current.user.issue_phone_link_code!
    @number = Assistant.texting_number
    respond_to do |format|
      format.turbo_stream
      format.html { render :show }
    end
  end
end
