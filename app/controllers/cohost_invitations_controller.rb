class CohostInvitationsController < ApplicationController
  include EventScoped
  before_action { authorize! :manage_cohosts }

  def destroy
    invitation = @event.cohost_invitations.find(params[:id])
    invitation.destroy!
    redirect_to event_cohosts_path(@event), notice: "Invitation for #{invitation.email} revoked.", status: :see_other
  end
end
