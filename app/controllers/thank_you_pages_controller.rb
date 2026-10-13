# The thank-you a guest opens from their text or email. No account; the token is the credential.
class ThankYouPagesController < ApplicationController
  allow_unauthenticated_access
  layout "guest"

  before_action :set_private_headers
  before_action :set_thank_you
  rate_limit to: 10, within: 10.minutes, only: :heart, by: -> { params[:token].to_s.first(16) },
    with: -> { redirect_to thank_you_page_path(params[:token]) }

  def show
    unless host_viewing?
      first_view = @thank_you.viewed_at.nil?
      @thank_you.update_column(:viewed_at, Time.current) if first_view
      Activity.record(event: @event, guest: @thank_you.guest, action: "thank_you_viewed", data: { name: @thank_you.recipient_name }) if first_view
    end
  end

  def heart
    if @thank_you.hearted_at.nil?
      @thank_you.update_column(:hearted_at, Time.current)
      Activity.record(event: @event, guest: @thank_you.guest, action: "thank_you_hearted", data: { name: @thank_you.recipient_name })
    end
    redirect_to thank_you_page_path(params[:token]), notice: "Sent with love."
  end

  private
    def set_thank_you
      @thank_you = ThankYou.find_by_token(params[:token])
      return render("guest_invitations/invalid_link", status: :not_found) unless @thank_you

      @event = @thank_you.event
    end

    def set_private_headers
      response.headers["Referrer-Policy"] = "same-origin"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.headers["Cache-Control"] = "private, no-store"
    end

    def host_viewing?
      resume_session && @event.role_for(Current.user).present?
    end
end
