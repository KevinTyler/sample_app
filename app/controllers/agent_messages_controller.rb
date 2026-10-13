# Messages to the agent from the web, and the replies as they arrive (the page polls `index` with
# the last message it has until the agent has answered).
class AgentMessagesController < ApplicationController
  MAX_UPLOAD = ThankYou::MEDIA_MAX_SIZE

  rate_limit to: 30, within: 1.minute, only: :create, by: -> { Current.user.id },
    with: -> { redirect_to agent_path, alert: "That's a lot of messages at once — give me a moment." }

  def index
    @conversation = AssistantConversation.for_web(Current.user)
    @messages = @conversation.messages.where("id > ?", params[:after].to_i).reorder(:created_at, :id).last(20)
    @waiting = @conversation.awaiting_reply?
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to agent_path }
    end
  end

  def create
    file = params[:file].presence
    return redirect_to(agent_path, alert: "That file is too large (the limit is 100 MB).") if file.respond_to?(:size) && file.size > MAX_UPLOAD

    @message = Assistant::Inbound.receive_web(user: Current.user, body: params[:body], file: file)
    respond_to do |format|
      format.turbo_stream { head :no_content unless @message }
      format.html { redirect_to agent_path }
    end
  end
end
