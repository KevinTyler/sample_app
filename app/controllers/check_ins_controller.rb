# The door: find a guest (search or QR pass), check their party in, undo mistakes.
class CheckInsController < ApplicationController
  include EventScoped
  before_action { authorize! :check_in }

  def index
    @query = params[:q].to_s.strip
    @show_all = params[:all] == "1"
    guests = @event.guests.order(:name)
    guests = guests.where(rsvp_status: %w[yes maybe]).or(guests.where.not(checked_in_at: nil)) unless @show_all
    guests = guests.search(@query) if @query.present?
    @guests = guests.limit(200)
    @expected = @event.attending_count
    @arrived = @event.guests.where.not(checked_in_at: nil).sum(:checked_in_count)
  end

  # Opened by scanning a guest's QR pass with any phone camera.
  def scan
    @guest = @event.guests.find_by_check_in_code(params[:code])
    render :invalid_code, status: :not_found unless @guest
  end

  def create
    guest = @event.guests.find(params[:guest_id])
    guest.check_in!(count: params[:count] || guest.party_size, by: current_user)
    redirect_back_or_to event_check_in_path(@event, q: params[:q].presence),
      notice: "#{guest.name} checked in#{" (party of #{guest.checked_in_count})" if guest.checked_in_count > 1}."
  end

  def destroy
    guest = @event.guests.find(params[:guest_id])
    guest.undo_check_in!(by: current_user)
    redirect_back_or_to event_check_in_path(@event), notice: "Check-in undone for #{guest.name}.", status: :see_other
  end
end
