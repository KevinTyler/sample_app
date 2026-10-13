# The schedule of a multi-part event (a wedding weekend, a festival, a conference with a dinner).
class ScheduleItemsController < ApplicationController
  include EventScoped
  before_action { authorize! :edit }
  before_action :set_item, only: %i[edit update destroy]

  def index
    @items = @event.schedule_items.includes(:replies).to_a
  end

  def new
    @item = @event.schedule_items.new(position: @event.schedule_items.count)
  end

  def create
    @item = @event.schedule_items.new(item_params.merge(position: @event.schedule_items.count))
    if @item.save
      redirect_to event_schedule_items_path(@event), notice: "Added “#{@item.name}” to the schedule."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @item.update(item_params)
      redirect_to event_schedule_items_path(@event), notice: "Updated “#{@item.name}”."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @item.destroy!
    redirect_to event_schedule_items_path(@event), notice: "Removed “#{@item.name}” (and its replies).", status: :see_other
  end

  private
    def set_item
      @item = @event.schedule_items.find(params[:id])
    end

    def item_params
      params.expect(schedule_item: [ :name, :starts_at_local, :ends_at_local, :location_name, :address, :description, :collects_replies, { audience_groups: [] } ])
    end
end
