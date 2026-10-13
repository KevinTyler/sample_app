# "Make one like this": guests who loved an invitation start their own from its design. Only the
# look carries over (template, colors, fonts, envelope) — never the host's words, photos or guests.
class StartsController < ApplicationController
  allow_unauthenticated_access only: :show

  def show
    @source = source_event
    return redirect_to(root_path) unless @source

    session[:start_from] = @source.share_token
    session[:return_to_after_authenticating] = start_url(from: @source.share_token) unless resume_session
    @design = InvitationDesign.for(@source)
  end

  def create
    source = source_event
    return redirect_to(new_event_path) unless source

    event = StartsController.start_from!(current_user, source)
    redirect_to edit_event_design_path(event), notice: "Here's your copy of the design — make it yours."
  end

  # Used after sign-up too (RegistrationsController).
  def self.start_from!(user, source)
    design = InvitationDesign.for(source).to_storage.except("message", "headline", "photo_style")
    event = user.owned_events.create!(user.event_defaults.merge(title: "My #{source.card_type_name.downcase}",
      time_zone: user.time_zone.presence || source.time_zone, card_type: source.card_type, design: design, inspired_by_event: source))
    Activity.record(event: event, user: user, action: "event_created")
    event
  end

  private
    def source_event
      token = params[:from].presence || session[:start_from]
      Event.where(status: %w[published]).find_by(share_token: token.to_s) if token.to_s.match?(/\A[A-Za-z0-9]{24}\z/)
    end
end
