# The signed-in host's own settings: name and how we tell them about replies.
class AccountsController < ApplicationController
  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    if @user.update(params.expect(user: %i[name rsvp_notifications]))
      redirect_to edit_account_path, notice: "Settings saved."
    else
      render :edit, status: :unprocessable_content
    end
  end
end
