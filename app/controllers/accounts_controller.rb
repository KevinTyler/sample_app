# The signed-in host's own settings: name, how we reach them, and their usual settings for new events.
class AccountsController < ApplicationController
  SETTINGS = %i[name rsvp_notifications agent_reach default_host_name time_zone phone_country_code default_allow_maybe
                default_track_kids default_plus_ones default_auto_nudge default_auto_day_before].freeze

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    if @user.update(params.expect(user: SETTINGS))
      redirect_to (params[:return_to] == "switch" ? switch_path : edit_account_path), notice: "Settings saved."
    else
      render (params[:return_to] == "switch" ? "switches/show" : :edit), status: :unprocessable_content
    end
  end
end
