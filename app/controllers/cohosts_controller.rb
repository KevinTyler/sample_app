# The owner's "Co-hosts" page: invite people by email with a role, change roles, remove access.
class CohostsController < ApplicationController
  include EventScoped
  before_action(except: :leave) { authorize! :manage_cohosts }
  rate_limit to: 20, within: 1.hour, only: :create, by: -> { current_user.id },
    with: -> { redirect_to event_cohosts_path(params[:event_id]), alert: "Too many invitations in a short time." }

  def index
    @memberships = @event.memberships.includes(:user).order(:created_at)
    @invitations = @event.cohost_invitations.pending.order(:created_at)
    @invitation = @event.cohost_invitations.new(role: "editor")
  end

  def create
    @invitation = @event.cohost_invitations.new(params.expect(cohost_invitation: %i[email role]).merge(invited_by: current_user))
    if @invitation.save
      CohostMailer.with(invitation: @invitation, token: @invitation.token).invite.deliver_later
      redirect_to event_cohosts_path(@event), notice: "Invitation sent to #{@invitation.email}."
    else
      @memberships = @event.memberships.includes(:user).order(:created_at)
      @invitations = @event.cohost_invitations.pending.order(:created_at)
      render :index, status: :unprocessable_content
    end
  end

  def update
    membership = @event.memberships.find(params[:id])
    membership.update!(role: params[:role].presence_in(EventMembership::ROLES.keys) || membership.role)
    redirect_to event_cohosts_path(@event), notice: "#{membership.user.name} is now #{membership.role_name.downcase}."
  end

  def destroy
    membership = @event.memberships.find(params[:id])
    membership.destroy!
    redirect_to event_cohosts_path(@event), notice: "#{membership.user.name} no longer has access.", status: :see_other
  end

  # A co-host removes themselves.
  def leave
    @event.memberships.find_by!(user: current_user).destroy!
    redirect_to events_path, notice: "You've left “#{@event.title}”.", status: :see_other
  end
end
