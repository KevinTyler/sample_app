# The invitation design editor: template, wording, fonts, colors, layout and uploaded artwork.
class EventDesignsController < ApplicationController
  include EventScoped
  before_action { authorize! :edit }

  def edit
    @design = @event.design_settings
  end

  def update
    @design = InvitationDesign.from_params(@event, design_params)
    # Assigning (rather than #attach) defers the upload until the record validates and saves.
    if params[:artwork].present?
      @event.artwork = params[:artwork]
    elsif params[:remove_artwork] == "1"
      @event.artwork = nil
    end

    if @design.valid? && @event.update(design: @design.to_storage)
      redirect_to event_path(@event), notice: "Design saved."
    else
      @design.errors.each { |error| @event.errors.add(:base, error.full_message) }
      render :edit, status: :unprocessable_content
    end
  end

  private
    def design_params
      params.fetch(:design, {}).permit(*InvitationDesign.attribute_names)
    end
end
