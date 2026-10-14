class ApplicationMailer < ActionMailer::Base
  # MAIL_FROM may be present but blank (e.g. left empty in a hosting dashboard): treat that as unset.
  def self.from_address
    ENV["MAIL_FROM"].presence || "Cordially <invitations@cordially.localhost>"
  end

  default from: -> { ApplicationMailer.from_address }
  layout "mailer"
end
