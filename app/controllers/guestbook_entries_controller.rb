# Hosts hide or restore guestbook notes.
class GuestbookEntriesController < ApplicationController
  include EventScoped
  before_action { authorize! :edit }

  def update
    entry = @event.guestbook_entries.find(params[:id])
    entry.update!(hidden_at: params[:hidden] == "1" ? Time.current : nil)
    redirect_to event_path(@event, anchor: "guestbook"), notice: entry.hidden? ? "Note hidden from guests." : "Note visible again.", status: :see_other
  end
end
