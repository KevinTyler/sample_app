class AssistantMailer < ApplicationMailer
  def link_phone
    @user = params[:user]
    @url = params[:url]
    mail(to: @user.email_address, subject: "Connect your phone to Cordially")
  end
end
