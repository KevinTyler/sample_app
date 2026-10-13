# "Today": the signed-in home is a conversation with the Cordially agent — the same agent hosts can
# text — with what needs them and their events alongside. The agent does the work; the rest of the
# app is where it (or the host) goes to look closer.
class AgentController < ApplicationController
  def show
    @conversation = AssistantConversation.for_web(Current.user)
    if params[:event_id] && (event = Current.user.accessible_events.find_by(id: params[:event_id]))
      @conversation.update!(event: event)
    end
    @messages = @conversation.recent_messages(40)
    @waiting = @conversation.awaiting_reply?
    @proposals = Current.user.agent_proposals.pending.recent_first.includes(:event).limit(6).to_a
    @events = Current.user.accessible_events.where.not(status: "cancelled")
      .where("starts_at IS NULL OR starts_at > ?", 1.day.ago).order(Arel.sql("starts_at IS NULL, starts_at")).limit(5)
    @prompt = params[:prompt].to_s.first(500)
  end
end
