class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 1.hour, only: :create, with: -> { redirect_to new_registration_path, alert: "Too many sign-up attempts. Please try again later." }

  def new
    redirect_to events_path if authenticated?
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[name email_address password password_confirmation]))
    if @user.save
      start_new_session_for @user
      redirect_to events_path, notice: "Welcome to Larkspur, #{@user.first_name}! Let's plan your first event."
    else
      render :new, status: :unprocessable_content
    end
  end
end
