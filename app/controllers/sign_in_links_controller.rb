# One-time sign-in links from the texting assistant. Opening the link shows a button rather than
# signing in right away, so link previews (which fetch URLs) can't use up the link.
class SignInLinksController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 20, within: 10.minutes, by: -> { request.remote_ip }, with: -> { head :too_many_requests }

  before_action { response.headers["Referrer-Policy"] = "same-origin" }

  def show
    @link = SignInLink.find_usable(params[:token])
    render :expired, status: :not_found unless @link
  end

  def create
    link = SignInLink.find_usable(params[:token])
    return render(:expired, status: :not_found) unless link&.consume!

    terminate_session if authenticated?
    start_new_session_for(link.user)
    redirect_to link.redirect_path
  end
end
