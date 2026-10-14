# Development-only view of captured emails and SMS (routes exist only when config.x.outbox_enabled).
class Dev::OutboxController < ApplicationController
  allow_unauthenticated_access
  include OutboxProtection

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
end
