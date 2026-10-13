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
    @event.show_ride_links = params.dig(:event, :show_ride_links) == "1" if params.dig(:event, :show_ride_links)

    saved = false
    Event.transaction do
      saved = @design.valid? && @event.update(design: @design.to_storage) && save_links && save_photos
      raise ActiveRecord::Rollback unless saved
    end

    if saved
      remove_photos
      redirect_to event_path(@event), notice: "Design saved."
    else
      @design.errors.each { |error| @event.errors.add(:base, error.full_message) }
      render :edit, status: :unprocessable_content
    end
  end

  private
    # The card back's links, edited as rows: blank rows are ignored, ticked ones removed.
    def save_links
      @links = []
      rows = params.fetch(:links, {}).to_unsafe_h.values.first(EventLink::MAX_PER_EVENT + 2)
      existing = @event.links.index_by(&:id)
      keep = []
      rows.each do |row|
        link = existing[row["id"].to_i] || @event.links.new
        if row["_destroy"] == "1" || row["url"].blank?
          link.destroy! if link.persisted?
          next
        end
        link.assign_attributes(url: row["url"].to_s.first(500), label: row["label"].to_s.first(60),
          kind: row["kind"].presence_in(EventLink::KINDS.keys) || (link.persisted? ? link.kind : nil), position: keep.size)
        @links << link
        keep << link
      end
      return false unless keep.all?(&:valid?)

      keep.each(&:save!)
      true
    end

    def remove_photo_ids
      Array(params[:remove_photo_ids]).map(&:to_i)
    end

    def remove_photos
      @event.photos.attachments.select { |a| a.id.in?(remove_photo_ids) }.each(&:purge_later)
    end

    def save_photos
      remove_ids = remove_photo_ids
      files = Array(params[:photos]).select { |f| f.respond_to?(:content_type) }
      return true if files.empty?

      remaining = @event.photos.attachments.count { |a| !a.id.in?(remove_ids) }
      if remaining + files.size > Event::MAX_PHOTOS
        @event.errors.add(:base, "You can have up to #{Event::MAX_PHOTOS} photos")
      elsif (bad = files.find { |f| !f.content_type.in?(Event::ARTWORK_TYPES) || f.size > Event::ARTWORK_MAX_SIZE })
        @event.errors.add(:base, "“#{bad.original_filename}” must be a PNG, JPEG, WebP or GIF under 8 MB")
      else
        @event.photos.attach(files)
        return true
      end
      false
    end

    def design_params
      params.fetch(:design, {}).permit(*InvitationDesign.attribute_names)
    end
end
