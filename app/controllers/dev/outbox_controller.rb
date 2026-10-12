# Development-only view of captured emails and SMS (routes exist only when config.x.outbox_enabled).
class Dev::OutboxController < ApplicationController
  allow_unauthenticated_access
  before_action :protect_outside_local_environments

  def index
    @items = OutboxItem.recent.limit(100)
  end

  def show
    @item = OutboxItem.find(params[:id])
  end

  # Raw email HTML, rendered inside a sandboxed iframe on the show page.
  def html
    item = OutboxItem.find(params[:id])
    response.headers["Content-Security-Policy"] = "sandbox; default-src 'none'; img-src * data:; style-src 'unsafe-inline'"
    render html: item.html_body.to_s.html_safe, layout: false # rubocop:disable Rails/OutputSafety
  end

  def clear
    OutboxItem.delete_all
    redirect_to dev_outbox_index_path, notice: "Outbox cleared.", status: :see_other
  end

  private
    # The outbox shows every guest's private link, so outside development/test it requires
    # ENABLE_OUTBOX=1 *and* HTTP basic auth with OUTBOX_PASSWORD.
    def protect_outside_local_environments
      return if Rails.env.local?

      password = ENV["OUTBOX_PASSWORD"].to_s
      return head(:forbidden) if password.length < 12

      http_basic_authenticate_or_request_with(name: "outbox", password: password, realm: "Outbox")
    end
end
