# Landing page for the link in a co-host invitation email.
class CohostAcceptancesController < ApplicationController
  allow_unauthenticated_access only: :show
  before_action :set_invitation
  rate_limit to: 30, within: 10.minutes, by: -> { request.remote_ip }, with: -> { head :too_many_requests }

  def show
    response.headers["Referrer-Policy"] = "no-referrer"
    unless authenticated?
      session[:return_to_after_authenticating] = request.url # come back here after signing in or up
      return
    end

    @mismatch = !@invitation.acceptable_by?(current_user) && @invitation.usable?
  end

  def create
    unless @invitation.acceptable_by?(current_user)
      return redirect_to(cohost_acceptance_path(params[:token]), alert: "This invitation can't be accepted by this account.")
    end

    @invitation.accept!(current_user)
    redirect_to event_path(@invitation.event), notice: "Welcome! You now have #{@invitation.role_name.downcase} access to “#{@invitation.event.title}”."
  end

  private
    def set_invitation
      @invitation = CohostInvitation.find_by_token(params[:token])
      render("invalid", status: :not_found) unless @invitation
    end
end
