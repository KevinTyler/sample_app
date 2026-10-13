# The gift log: who brought what. Hosts add gifts as they open them.
class GiftsController < ApplicationController
  include EventScoped
  before_action { authorize! :manage_guests }

  def create
    gift = @event.gifts.new(gift_params)
    if gift.save
      redirect_to event_thank_yous_path(@event, anchor: "gift-#{gift.id}"), notice: "Added: #{gift.description} from #{gift.giver_name}."
    else
      redirect_to event_thank_yous_path(@event), alert: "Couldn't add that gift: #{gift.errors.full_messages.to_sentence}."
    end
  end

  def update
    gift = @event.gifts.find(params[:id])
    if gift.update(gift_params)
      redirect_to event_thank_yous_path(@event), notice: "Gift updated."
    else
      redirect_to event_thank_yous_path(@event), alert: gift.errors.full_messages.to_sentence
    end
  end

  def destroy
    gift = @event.gifts.find(params[:id])
    gift.destroy!
    redirect_to event_thank_yous_path(@event), notice: "Removed #{gift.description}.", status: :see_other
  end

  private
    def gift_params
      permitted = params.expect(gift: %i[guest_id giver_name description notes])
      permitted[:guest_id] = @event.guests.find_by(id: permitted[:guest_id])&.id if permitted.key?(:guest_id)
      permitted
    end
end
