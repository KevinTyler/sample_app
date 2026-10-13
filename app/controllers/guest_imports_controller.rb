class GuestImportsController < ApplicationController
  include EventScoped
  before_action { authorize! :manage_guests }
  before_action :set_import, only: %i[show confirm destroy]
  rate_limit to: 30, within: 1.hour, only: :create, by: -> { current_user.id },
    with: -> { redirect_to event_path(params[:event_id]), alert: "Too many imports in a short time. Please wait a bit." }

  def new
    @import = @event.guest_imports.new
  end

  def create
    @event.guest_imports.stale.delete_all
    @import = @event.guest_imports.new(user: current_user, update_existing: params[:update_existing] == "1")
    if (file = params[:file]).present?
      if file.size > GuestImport::MAX_BYTES
        @import.errors.add(:base, "That file is too large (the limit is 1 MB).")
        return render(:new, status: :unprocessable_content)
      end
      @import.filename = file.original_filename.to_s.first(200)
      @import.csv_data = file.read
    else
      @import.csv_data = params[:pasted].to_s
    end

    if @import.save
      redirect_to event_guest_import_path(@event, @import)
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    redirect_to event_path(@event), notice: "That import was already applied." unless @import.pending?
  end

  def confirm
    return redirect_to(event_path(@event), notice: "That import was already applied.") unless @import.pending?

    summary = @import.apply!(by: current_user)
    redirect_to event_guests_path(@event),
      notice: "Import complete: #{summary['created']} added, #{summary['updated']} updated, #{summary['skipped']} skipped."
  end

  def destroy
    @import.destroy!
    redirect_to event_guests_path(@event), notice: "Import discarded.", status: :see_other
  end

  # A starter spreadsheet showing the columns we understand.
  def template
    csv = CSV.generate do |rows|
      rows << [ "Name", "Email", "Phone", "Group", "Plus ones", "Notes" ]
      rows << [ "Dana Whitfield", "dana@example.com", "+1 555 010 2000", "Family", "1", "Vegetarian" ]
      rows << [ "Lee Park", "lee@example.com", "", "Work", "0", "" ]
    end
    send_data csv, filename: "cordially-guest-list-template.csv", type: "text/csv"
  end

  private
    def set_import
      @import = @event.guest_imports.find(params[:id])
    end
end
