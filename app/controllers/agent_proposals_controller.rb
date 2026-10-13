# Approving or dismissing something the agent proposed, with a tap on the web. The outcome is
# posted to the conversation like any other reply.
class AgentProposalsController < ApplicationController
  before_action :set_proposal

  def approve
    outcome = begin
      @proposal.approve!(by: Current.user)
    rescue Assistant::Error => e
      e.message
    end
    respond(outcome)
  end

  def dismiss
    @proposal.dismiss!
    respond("Okay — I'll leave that one.")
  end

  private
    def set_proposal
      @proposal = Current.user.agent_proposals.find(params[:id])
    end

    def respond(text)
      AssistantConversation.for_web(Current.user).reply!(text, cards: [ { "type" => "proposal", "proposal_id" => @proposal.id } ])
      if @proposal.reload.kind == "thank_yous" && @proposal.status == "done" && @proposal.event
        redirect_to event_thank_yous_path(@proposal.event), status: :see_other
      else
        redirect_to agent_path(anchor: "latest"), status: :see_other
      end
    end
end
